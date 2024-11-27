import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

part 'db.g.dart';

// Initialize Firestore instance
final firestore.FirebaseFirestore firestoreInstance =
    firestore.FirebaseFirestore.instance;

@collection
class Settings {
  Id id = Isar.autoIncrement;
  bool onboard = false;
  String? theme = 'system';
  String timeformat = '24';
  bool materialColor = true;
  bool amoledTheme = false;
  bool? isImage = true;
  String? language;
  String firstDay = 'monday';
}

@collection
class Tasks {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String? firestoreId; // Firestore ID for uniqueness

  String title;
  String description = '';
  int taskColor = 0;
  bool archive = false;
  int? index;

  @Backlink(to: 'task') // Links todos to tasks
  final todos = IsarLinks<Todos>();

  Tasks({
    this.firestoreId,
    required this.title,
    this.description = '',
    this.archive = false,
    required this.taskColor,
    this.index,
  });

  // Fetch tasks from Firestore
  static Future<List<Map<String, dynamic>>> fetchTasks(String uid) async {
    try {
      final snapshot = await firestoreInstance
          .collection('tasks')
          .where('uid', isEqualTo: uid)
          .get();
      return snapshot.docs
          .map((doc) => {'firestoreId': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      throw Exception('Error fetching tasks: $e');
    }
  }

  // Add task to Firestore
  Future<void> addTaskToFirestore(String uid) async {
    try {
      final docRef = await firestoreInstance.collection('tasks').add({
        'uid': uid,
        'title': title,
        'description': description,
        'taskColor': taskColor,
        'archive': archive,
        'createdAt': firestore.FieldValue.serverTimestamp(),
      });
      firestoreId = docRef.id;
    } catch (e) {
      throw Exception('Failed to add task to Firestore: $e');
    }
  }

  // Update task in Firestore
  Future<void> updateTaskInFirestore() async {
    if (firestoreId == null) return;
    try {
      await firestoreInstance.collection('tasks').doc(firestoreId).update({
        'title': title,
        'description': description,
        'taskColor': taskColor,
        'archive': archive,
      });
    } catch (e) {
      throw Exception('Failed to update task in Firestore: $e');
    }
  }

  // Delete task from Firestore
  Future<void> deleteTaskFromFirestore() async {
    if (firestoreId == null) return;
    try {
      await firestoreInstance.collection('tasks').doc(firestoreId).delete();
    } catch (e) {
      throw Exception('Failed to delete task from Firestore: $e');
    }
  }
}

@collection
class Todos {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String? firestoreId; // Unique Firestore ID
  String name;
  String description = '';
  DateTime? todoCompletedTime;
  DateTime createdTime = DateTime.now();
  bool done = false;
  bool fix = false;

  @enumerated
  Priority priority = Priority.none;

  List<String> tags = [];
  int? index;

  final task = IsarLink<Tasks>();

  // Add category_id to link todos with tasks
  @Index()
  String? categoryId;

  Todos({
    this.firestoreId,
    required this.name,
    this.description = '',
    this.todoCompletedTime,
    required this.createdTime,
    this.done = false,
    this.fix = false,
    this.priority = Priority.none,
    this.tags = const [],
    this.categoryId, // Initialize category_id
    this.index,
  });

  // Fetch todos from Firestore
  static Future<List<Map<String, dynamic>>> fetchTodos(String uid) async {
    try {
      final snapshot = await firestoreInstance
          .collection('todos')
          .where('uid', isEqualTo: uid)
          .get();
      return snapshot.docs
          .map((doc) => {'firestoreId': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      throw Exception('Error fetching todos: $e');
    }
  }

  // Add todo to Firestore
  Future<void> addTodoToFirestore(String uid, String taskFirestoreId) async {
    try {
      final docRef = await firestoreInstance.collection('todos').add({
        'uid': uid,
        'category_id': taskFirestoreId, // Save category_id (linked task ID)
        'title': name,
        'description': description,
        'todoCompletedTime': todoCompletedTime?.toIso8601String(),
        'createdTime': createdTime.toIso8601String(),
        'done': done,
        'fix': fix,
        'priority_level': priority.name,
      });
      firestoreId = docRef.id;
    } catch (e) {
      throw Exception('Failed to add todo to Firestore: $e');
    }
  }

  // Update todo in Firestore
  Future<void> updateTodoInFirestore() async {
    if (firestoreId == null) return;
    try {
      await firestoreInstance.collection('todos').doc(firestoreId).update({
        'name': name,
        'description': description,
        'todoCompletedTime': todoCompletedTime?.toIso8601String(),
        'done': done,
        'fix': fix,
        'priority': priority.name,
        'category_id': categoryId, // Ensure category_id is updated
      });
    } catch (e) {
      throw Exception('Failed to update todo in Firestore: $e');
    }
  }

  // Delete todo from Firestore
  Future<void> deleteTodoFromFirestore() async {
    if (firestoreId == null) return;
    try {
      await firestoreInstance.collection('todos').doc(firestoreId).delete();
    } catch (e) {
      throw Exception('Failed to delete todo from Firestore: $e');
    }
  }
}

enum Priority {
  high(name: 'highPriority', color: Colors.red),
  medium(name: 'mediumPriority', color: Colors.orange),
  low(name: 'lowPriority', color: Colors.green),
  none(name: 'noPriority');

  const Priority({
    required this.name,
    this.color,
  });

  final String name;
  final Color? color;
}

@collection
class Notifications {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String? firestoreId;

  String title;
  String description;
  DateTime createdAt;

  Notifications({
    this.firestoreId,
    required this.title,
    required this.description,
    required this.createdAt,
  });
}

class DatabaseSync {
  final Isar isar;

  DatabaseSync(this.isar);

  Future<void> syncUserData(String userUid) async {
    try {
      // Fetch tasks and todos from Firestore
      final tasksData = await Tasks.fetchTasks(userUid);
      final todosData = await Todos.fetchTodos(userUid);

      // Sync tasks
      for (var taskMap in tasksData) {
        final firestoreId = taskMap['firestoreId'] as String?;
        final existingTask =
            isar.tasks.filter().firestoreIdEqualTo(firestoreId).findFirstSync();

        await isar.writeTxn(() async {
          if (existingTask != null) {
            // Update existing task
            existingTask
              ..title = taskMap['title'] as String
              ..description = taskMap['description'] ?? ''
              ..taskColor = taskMap['taskColor'] ?? 0
              ..archive = taskMap['archive'] ?? false;
            await isar.tasks.put(existingTask);
          } else {
            // Add new task
            final newTask = Tasks(
              firestoreId: firestoreId,
              title: taskMap['title'] as String,
              description: taskMap['description'] ?? '',
              taskColor: taskMap['taskColor'] ?? 0,
              archive: taskMap['archive'] ?? false,
            );
            await isar.tasks.put(newTask);
          }
        });
      }

      // Sync todos
      for (var todoMap in todosData) {
        final firestoreId = todoMap['firestoreId'] as String?;
        final existingTodo =
            isar.todos.filter().firestoreIdEqualTo(firestoreId).findFirstSync();

        await isar.writeTxn(() async {
          if (existingTodo != null) {
            // Update existing todo
            existingTodo
              ..name = todoMap['name'] as String
              ..description = todoMap['description'] ?? ''
              ..todoCompletedTime = _parseDateTime(todoMap['todoCompletedTime'])
              ..createdTime = _parseDateTime(todoMap['createdTime'])
              ..done = todoMap['done'] ?? false
              ..fix = todoMap['fix'] ?? false
              ..priority = _parsePriority(todoMap['priority']);
            await isar.todos.put(existingTodo);
          } else {
            // Add new todo
            final newTodo = Todos(
              firestoreId: firestoreId,
              name: todoMap['name'] as String,
              description: todoMap['description'] ?? '',
              todoCompletedTime: _parseDateTime(todoMap['todoCompletedTime']),
              createdTime: _parseDateTime(todoMap['createdTime']),
              done: todoMap['done'] ?? false,
              fix: todoMap['fix'] ?? false,
              priority: _parsePriority(todoMap['priority']),
            );

            // Link todo to task
            final taskFirestoreId = todoMap['taskId'] as String?;
            if (taskFirestoreId != null) {
              final task = isar.tasks
                  .filter()
                  .firestoreIdEqualTo(taskFirestoreId)
                  .findFirstSync();
              if (task != null) {
                newTodo.task.value = task;
              }
            }

            await isar.todos.put(newTodo);
          }
        });
      }

      print("Data sync completed successfully.");
    } catch (e) {
      print("Error syncing user data: $e");
      throw Exception('Error syncing user data: $e');
    }
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is firestore.Timestamp) return value.toDate();
    return DateTime.now();
  }

  Priority _parsePriority(dynamic value) {
    if (value is String) {
      return Priority.values.firstWhere(
        (p) => p.name == value,
        orElse: () => Priority.none,
      );
    }
    return Priority.none;
  }
}
