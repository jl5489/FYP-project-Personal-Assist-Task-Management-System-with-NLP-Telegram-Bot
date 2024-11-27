import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';
import '../data/db.dart' as local;
import 'package:cloud_firestore/cloud_firestore.dart';

class IsarController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  late final Isar isar;
  final now = DateTime.now();
  final bool _isDebugMode = true;
  final _syncStats = {
    'tasks': {'success': 0, 'failed': 0},
    'todos': {'success': 0, 'failed': 0},
    'notifications': {'success': 0, 'failed': 0},
  };

  String? currentUserId;

  void _logDebug(String message) {
    if (_isDebugMode) {
      print('IsarDebug: $message');
    }
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    try {
      await openDB();
    } catch (e) {
      print("Error initializing database: $e");
    }
  }

  // Add debug flags and counters
  Future<Isar> openDB() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationSupportDirectory();
      isar = await Isar.open(
        [
          local.TasksSchema,
          local.TodosSchema,
          local.SettingsSchema,
          local.NotificationsSchema,
        ],
        directory: dir.path,
        inspector: true,
      );
    } else {
      isar = Isar.getInstance()!;
    }
    _logDebug("Isar database initialized.");
    return isar;
  }

  // Map Todo object to Firestore format
  Map<String, dynamic> _mapTodoToFirestore(local.Todos todo) {
    return {
      'title': todo.name,
      'description': todo.description,
      'created_at': todo.createdTime.toIso8601String(),
      'completed_at': todo.todoCompletedTime?.toIso8601String(),
      'status': todo.done ? 'completed' : 'pending',
      'is_fixed': todo.fix,
      'priority_level': todo.priority.name,
      'tags': todo.tags,
    };
  }

  // Map Firestore document to local Todo object
  local.Todos _mapFirestoreToTodo(Map<String, dynamic> data) {
    return local.Todos(
      name: data['title'] ?? 'Untitled Todo',
      description: data['description'] ?? '',
      createdTime: _parseDateTime(data['created_at']),
      todoCompletedTime: _parseDateTime(data['completed_at']),
      done: data['status'] == 'completed',
      fix: data['is_fixed'] ?? false,
      priority: _parsePriority(data['priority_level']),
      tags: List<String>.from(data['tags'] ?? []),
      firestoreId: data['id'],
    );
  }

  Future<void> syncDataWithFirestore({
    required String currentUserId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> todos,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
  }) async {
    try {
      await verifyDatabaseConnection();
      _logDebug('Starting sync process...');
      await clearDatabase();
      _logDebug('Database cleared successfully, starting sync...');

      // First, create a map of task IDs to task objects
      final Map<String, local.Tasks> taskMap = {};
      final List<local.Tasks> tasksToSave = [];

      // Process tasks first
      for (var taskDoc in tasks) {
        final taskData = taskDoc.data();
        final taskId = taskDoc.id;

        final task = local.Tasks(
          firestoreId: taskId,
          title: taskData['title'] ?? 'Untitled Task',
          description: taskData['description'] ?? '',
          taskColor:
              int.tryParse(taskData['taskColor']?.toString() ?? '0') ?? 0,
          archive: taskData['archive'] ?? false,
        );

        taskMap[taskId] = task;
        tasksToSave.add(task);
      }

      // Save all tasks first
      await isar.writeTxn(() async {
        await isar.tasks.putAll(tasksToSave);
      });

      // Process todos and link them to tasks
      final List<local.Todos> todosToSave = [];
      for (var todoDoc in todos) {
        final todoData = todoDoc.data();
        final categoryId = todoData['category_id'] as String?;

        // Find the corresponding task using category_id
        final parentTask = taskMap[categoryId];
        if (parentTask == null) {
          _logDebug(
              'No matching task found for todo ${todoDoc.id} with category_id $categoryId');
          continue;
        }

        final todo = local.Todos(
          firestoreId: todoDoc.id,
          name: todoData['title'] ?? 'Untitled Todo',
          description: todoData['description'] ?? '',
          createdTime: _parseDateTime(todoData['createdAt']),
          todoCompletedTime: _parseDateTime(todoData['due_date']),
          done: todoData['task_status'] == 'completed',
          fix: todoData['reminder_time'] != null,
          priority: _parsePriority(todoData['priority_level']),
          tags: List<String>.from(todoData['tags'] ?? []),
        );

        // Set the task relationship
        todo.task.value = parentTask;
        todosToSave.add(todo);
      }

      // Save all todos with their task relationships
      await isar.writeTxn(() async {
        for (var todo in todosToSave) {
          await isar.todos.put(todo);
          await todo.task.save(); // Save the task relationship
        }
      });

      // Process notifications
      final List<local.Notifications> notificationsToSave = [];
      for (var notificationDoc in notifications) {
        final notificationData = notificationDoc.data();
        final notification = local.Notifications(
          firestoreId: notificationDoc.id,
          title: notificationData['title'] ?? 'Untitled Notification',
          description: notificationData['description'] ?? '',
          createdAt: _parseDateTime(notificationData['createdAt']),
        );
        notificationsToSave.add(notification);
      }

      // Save notifications
      await isar.writeTxn(() async {
        await isar.notifications.putAll(notificationsToSave);
      });

      _logDebug('Sync completed successfully');
      await verifySync(); // Verify the sync results
    } catch (e) {
      _logDebug('Error during sync: $e');
      throw Exception('Sync failed: $e');
    }
  }

  Future<void> updateTodosWithMissingTaskIds() async {
    final todosSnapshot = await firestore.collection('todos').get();
    final tasksSnapshot = await firestore.collection('tasks').get();

    // Create a map of task titles to Firestore IDs for easier matching
    final taskMap = {
      for (var task in tasksSnapshot.docs) task.data()['title']: task.id
    };

    // Update todos missing a taskId
    for (var todoDoc in todosSnapshot.docs) {
      final todoData = todoDoc.data();

      if (todoData['taskId'] == null || todoData['taskId'].isEmpty) {
        final linkedTaskId =
            taskMap[todoData['title']]; // Replace this with your matching logic
        if (linkedTaskId != null) {
          await firestore.collection('todos').doc(todoDoc.id).update({
            'taskId': linkedTaskId,
          });
          print('Updated Todo ${todoDoc.id} with taskId $linkedTaskId');
        } else {
          print('No matching task found for Todo ${todoDoc.id}');
        }
      }
    }
  }

  Future<void> verifySync() async {
    try {
      // Fetch all tasks from Isar
      final tasks = await isar.tasks.where().findAll();
      final todos = await isar.todos.where().findAll();
      final notifications = await isar.notifications.where().findAll();

      print('Verification Report:');
      print('Tasks: ${tasks.length}');
      for (var task in tasks) {
        print(
            '- Task ID: ${task.id}, Title: ${task.title}, Firestore ID: ${task.firestoreId}');
      }

      print('\nTodos: ${todos.length}');
      for (var todo in todos) {
        await todo.task.load();
        print(
            '- Todo: ${todo.name}, Linked Task: ${todo.task.value?.title ?? "No task"}');
      }

      print('\nNotifications: ${notifications.length}');
      for (var notification in notifications) {
        print(
            '- Notification ID: ${notification.id}, Title: ${notification.title}, Firestore ID: ${notification.firestoreId}');
      }

      print('Sync verification completed successfully.');
    } catch (e) {
      print('Error during sync verification: $e');
    }
  }

  // Create backup
  Future<void> createBackUp() async {
    print("Starting backup process...");
    await verifyDatabaseConnection();

    final backupDir = await getDirectoryPath();
    if (backupDir == null) {
      EasyLoading.showInfo('Please select a valid directory for backup.');
      return;
    }

    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final backupFileName = 'backup_todark_db_$timestamp.isar';
      final backupFile = File('$backupDir/$backupFileName');

      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      await isar.copyToFile(backupFile.path);
      EasyLoading.showSuccess('Database backup completed successfully.');

      // Backup Firestore tasks and todos
      List<local.Tasks> tasks = await isar.tasks.where().findAll();
      for (var task in tasks) {
        DocumentReference taskDoc = await firestore.collection('tasks').add({
          'title': task.title,
          'description': task.description,
          'taskColor': task.taskColor,
          'archive': task.archive,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await task.todos.load();
        for (var todo in task.todos) {
          await firestore.collection('todos').add({
            'name': todo.name,
            'description': todo.description,
            'createdTime': todo.createdTime.toIso8601String(),
            'done': todo.done,
            'fix': todo.fix,
            'priority': todo.priority.toString(),
            'tags': todo.tags,
            'taskId': taskDoc.id,
          });
        }
      }
      print("Backup to Firestore completed successfully.");
    } catch (e) {
      EasyLoading.showError('Error during backup: $e');
    }
  }

  // Restore database
  Future<void> restoreDB() async {
    final dbDirectory = await getApplicationSupportDirectory();
    final XFile? backupFile = await openFile();

    if (backupFile == null) {
      EasyLoading.showInfo('No backup file selected.');
      return;
    }

    try {
      await isar.close();
      final dbFile = File(backupFile.path);
      final dbPath = p.join(dbDirectory.path, 'default.isar');

      if (await dbFile.exists()) {
        await dbFile.copy(dbPath);
      }
      EasyLoading.showSuccess('Database restored successfully.');

      await isar.writeTxn(() async {
        await isar.tasks.clear();
        await isar.todos.clear();
        await isar.notifications.clear(); // Add this if notifications are used
      });
      print("Isar database cleared successfully.");

      QuerySnapshot taskSnapshot = await firestore.collection('tasks').get();
      for (var doc in taskSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final task = local.Tasks(
          title: data['title'],
          description: data['description'] ?? '',
          taskColor: data['taskColor'],
          archive: data['archive'] ?? false,
        );

        await isar.writeTxn(() async {
          await isar.tasks.put(task);
        });

        QuerySnapshot todoSnapshot = await firestore
            .collection('todos')
            .where('taskId', isEqualTo: doc.id)
            .get();

        for (var todoDoc in todoSnapshot.docs) {
          final todoData = todoDoc.data() as Map<String, dynamic>;
          final todo = local.Todos(
            name: todoData['name'],
            description: todoData['description'] ?? '',
            createdTime: DateTime.parse(todoData['createdTime']),
            done: todoData['done'] ?? false,
            fix: todoData['fix'] ?? false,
            priority: local.Priority.values.firstWhere(
              (e) => e.toString() == 'Priority.${todoData['priority']}',
              orElse: () => local.Priority.none,
            ),
            tags: List<String>.from(todoData['tags']),
          );

          await isar.writeTxn(() async {
            await isar.todos.put(todo);
            todo.task.value = task;
            await todo.task.save();
          });
        }
      }
      print("Database restoration completed successfully.");
      Restart.restartApp();
    } catch (e) {
      EasyLoading.showError('Error during restoration: $e');
    }
  }

  // Clear database
  Future<void> clearDatabase() async {
    try {
      await verifyDatabaseConnection();

      await isar.writeTxn(() async {
        // First, clear all relationships in todos
        final todos = await isar.todos.where().findAll();
        for (final todo in todos) {
          todo.task.value = null;
          await todo.task.save();
        }

        // Then clear all collections
        await Future.wait([
          isar.todos.clear(),
          isar.tasks.clear(),
          isar.notifications.clear(),
          isar.settings.clear(),
        ]);
      });

      _logDebug("Database cleared successfully");

      // Verify the clearing
      final remainingTodos = await isar.todos.count();
      final remainingTasks = await isar.tasks.count();
      final remainingNotifications = await isar.notifications.count();

      if (remainingTodos > 0 ||
          remainingTasks > 0 ||
          remainingNotifications > 0) {
        throw Exception(
            "Database not fully cleared. Remaining items: Todos: $remainingTodos, Tasks: $remainingTasks, Notifications: $remainingNotifications");
      }
    } catch (e) {
      _logDebug("Error clearing database: $e");
      throw Exception("Failed to clear database: $e");
    }
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  local.Priority _parsePriority(dynamic value) {
    if (value == null) return local.Priority.none;
    if (value is String) {
      return local.Priority.values.firstWhere(
        (e) =>
            e.toString().split('.').last.toLowerCase() == value.toLowerCase(),
        orElse: () => local.Priority.none,
      );
    }
    return local.Priority.none;
  }

  Future<void> verifyDatabaseConnection() async {
    if (!isar.isOpen) {
      await openDB();
      if (!isar.isOpen) {
        throw Exception("Failed to establish database connection.");
      }
    }
  }
}
