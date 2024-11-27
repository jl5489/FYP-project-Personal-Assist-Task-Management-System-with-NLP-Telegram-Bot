import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:todark/app/data/db.dart';
import 'package:todark/app/utils/notification.dart';
import 'package:todark/main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TodoController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Observables
  final tasks = <Tasks>[].obs;
  final todos = <Todos>[].obs;
  final selectedTask = <Tasks>[].obs;
  final selectedTodo = <Todos>[].obs;
  final isMultiSelectionTask = false.obs;
  final isMultiSelectionTodo = false.obs;
  final isPop = true.obs;

  final duration = const Duration(milliseconds: 500);
  var now = DateTime.now();
  String? currentUserId;
  final bool _isDebugMode = true;
  final _syncStats = {
    'tasks': {'success': 0, 'failed': 0},
    'todos': {'success': 0, 'failed': 0},
    'notifications': {'success': 0, 'failed': 0},
  };

  void _logDebug(String message) {
    if (_isDebugMode) {
      print('IsarDebug: $message');
    }
  }

  @override
  void onInit() {
    super.onInit();
    fetchLocalData();
  }

  /// Sets the current user ID
  void setCurrentUserId(String uid) {
    currentUserId = uid;
  }

  void clearData() {
    tasks.clear();
    todos.clear();
    selectedTask.clear();
    selectedTodo.clear();
    isMultiSelectionTask.value = false;
    isMultiSelectionTodo.value = false;
    isPop.value = true;
  }

  // Method to get current user ID
  String getCurrentUserId() {
    if (currentUserId == null) {
      throw Exception(
          'User ID not set. Make sure to call setCurrentUserId first.');
    }
    return currentUserId!;
  }

  void fetchLocalData() {
    tasks.assignAll(isar.tasks.where().findAllSync());
    todos.assignAll(isar.todos.where().findAllSync());

    for (var todo in todos) {
      // Ensure todos are linked to their tasks
      if (todo.task.value == null) {
        final associatedTask =
            tasks.firstWhereOrNull((task) => task.id == todo.task.value?.id);
        if (associatedTask != null) {
          todo.task.value = associatedTask;
          isar.writeTxnSync(() => todo.task.saveSync());
        }
      }
    }

    // Refresh UI
    tasks.refresh();
    todos.refresh();
  }

  Future<void> safelyAssociateTodoWithTask(Todos todo, String? taskId) async {
    if (taskId == null) {
      print('Warning: Todo ${todo.id} has no associated taskId');
      return;
    }

    final associatedTask =
        tasks.firstWhereOrNull((task) => task.firestoreId == taskId);
    if (associatedTask == null) {
      print(
          'Warning: Could not find task with id $taskId for todo ${todo.name}');
      return;
    }

    await isar.writeTxn(() async {
      todo.task.value = associatedTask;
      await isar.todos.put(todo);
      await todo.task.save();
    });
  }

  Future<void> fetchAndSyncData() async {
    try {
      if (currentUserId == null) {
        throw Exception("User ID is not set. Please log in.");
      }

      // Fetch tasks and todos from Firestore
      final taskSnapshot = await firestore
          .collection('tasks')
          .where('uid', isEqualTo: currentUserId)
          .get();

      final todoSnapshot = await firestore
          .collection('todos')
          .where('uid', isEqualTo: currentUserId)
          .get();

      // Clear local Isar database
      await isar.writeTxn(() async {
        await isar.tasks.clear();
        await isar.todos.clear();
      });

      // Save fetched tasks
      final List<Tasks> fetchedTasks = taskSnapshot.docs.map((doc) {
        final data = doc.data();
        return Tasks(
          firestoreId: doc.id,
          title: data['title'] ?? 'Untitled',
          description: data['description'] ?? '',
          taskColor: data['taskColor'] ?? 0,
          archive: data['archive'] ?? false,
        );
      }).toList();

      tasks.assignAll(fetchedTasks);
      await isar.writeTxn(() async => await isar.tasks.putAll(fetchedTasks));

      // Save fetched todos
      final List<Todos> fetchedTodos = todoSnapshot.docs.map((doc) {
        final data = doc.data();
        final todo = Todos(
          firestoreId: doc.id,
          name: data['name'] ?? 'Untitled',
          description: data['description'] ?? '',
          createdTime: data['createdTime'] != null
              ? DateTime.parse(data['createdTime'])
              : DateTime.now(),
          todoCompletedTime: data['todoCompletedTime'] != null
              ? DateTime.parse(data['todoCompletedTime'])
              : null,
        );

        // Associate todos with tasks
        final taskId = data['taskId'];
        if (taskId != null) {
          final associatedTask = fetchedTasks
              .firstWhereOrNull((task) => task.firestoreId == taskId);
          if (associatedTask != null) {
            todo.task.value = associatedTask;
          }
        }

        return todo;
      }).toList();

      todos.assignAll(fetchedTodos);
      await isar.writeTxn(() async => await isar.todos.putAll(fetchedTodos));

      print("Data sync completed successfully.");
    } catch (e) {
      print("Error syncing data: $e");
      EasyLoading.showError('Failed to sync data.');
    }
  }

  Future<void> verifyTodoRelationships() async {
    final todos = await isar.todos.where().findAll();
    int orphanedTodos = 0;

    for (var todo in todos) {
      await todo.task.load();
      if (todo.task.value == null) {
        orphanedTodos++;
        _logDebug('Orphaned todo found: ${todo.name}');
      }
    }

    if (orphanedTodos > 0) {
      _logDebug('Warning: Found $orphanedTodos orphaned todos');
    }
  }

  Future<void> addTask(String title, String desc, Color myColor) async {
    try {
      // Check for duplicates
      final existingTask =
          isar.tasks.filter().titleEqualTo(title).findFirstSync();
      if (existingTask != null) {
        throw Exception("A task with the same title already exists.");
      }

      final newTask = Tasks(
        title: title,
        description: desc,
        taskColor: myColor.value,
      );

      final docRef = await firestore.collection('tasks').add({
        'title': title,
        'description': desc,
        'taskColor': myColor.value,
        'createdAt': FieldValue.serverTimestamp(),
      });

      newTask.firestoreId = docRef.id;

      await isar.writeTxn(() => isar.tasks.put(newTask));
      tasks.add(newTask);

      EasyLoading.showSuccess("Task added successfully.");
    } catch (e) {
      print("Error adding task: $e");
      EasyLoading.showError('Failed to add task.');
    }
  }

  Future<void> deleteTask(List<Tasks> taskList) async {
    try {
      for (var task in taskList) {
        // Remove notifications
        final taskTodos =
            isar.todos.filter().task((q) => q.idEqualTo(task.id)).findAllSync();
        for (var todo in taskTodos) {
          if (todo.todoCompletedTime != null &&
              todo.todoCompletedTime!.isAfter(now)) {
            await flutterLocalNotificationsPlugin.cancel(todo.id);
          }
        }

        // Remove todos
        await isar.writeTxn(() =>
            isar.todos.filter().task((q) => q.idEqualTo(task.id)).deleteAll());

        // Remove task
        await isar.writeTxn(() => isar.tasks.delete(task.id));

        // Remove from Firestore
        await firestore.collection('tasks').doc(task.firestoreId).delete();
      }
      tasks.removeWhere((task) => taskList.contains(task));
      EasyLoading.showSuccess('Tasks deleted successfully.');
    } catch (e) {
      print("Error deleting tasks: $e");
      EasyLoading.showError('Failed to delete tasks.');
    }
  }

  Future<void> updateTask(
      Tasks task, String title, String desc, Color myColor) async {
    isar.writeTxnSync(() {
      task.title = title;
      task.description = desc;
      task.taskColor = myColor.value;
      isar.tasks.putSync(task);
    });

    var newTask = task;
    int oldIdx = tasks.indexOf(task);
    tasks[oldIdx] = newTask;
    tasks.refresh();

    // Update task in Firestore
    var docRef = await firestore
        .collection('tasks')
        .where('title', isEqualTo: task.title)
        .get();

    if (docRef.docs.isNotEmpty) {
      await firestore.collection('tasks').doc(docRef.docs.first.id).update({
        'title': title,
        'description': desc,
        'taskColor': myColor.value,
      });
    }

    EasyLoading.showSuccess('editCategory'.tr, duration: duration);
  }

  Future<void> archiveTask(List<Tasks> taskList) async {
    List<Tasks> taskListCopy = List.from(taskList);

    for (var task in taskListCopy) {
      // Delete Notification
      List<Todos> getTodo;
      getTodo =
          isar.todos.filter().task((q) => q.idEqualTo(task.id)).findAllSync();

      for (var todo in getTodo) {
        if (todo.todoCompletedTime != null) {
          if (todo.todoCompletedTime!.isAfter(now)) {
            await flutterLocalNotificationsPlugin.cancel(todo.id);
          }
        }
      }
      // Archive Task
      isar.writeTxnSync(() {
        task.archive = true;
        isar.tasks.putSync(task);
      });
      tasks.refresh();
      todos.refresh();
      EasyLoading.showSuccess('categoryArchive'.tr, duration: duration);
    }
  }

  Future<void> noArchiveTask(List<Tasks> taskList) async {
    List<Tasks> taskListCopy = List.from(taskList);

    for (var task in taskListCopy) {
      // Create Notification
      List<Todos> getTodo;
      getTodo =
          isar.todos.filter().task((q) => q.idEqualTo(task.id)).findAllSync();

      for (var todo in getTodo) {
        if (todo.todoCompletedTime != null) {
          if (todo.todoCompletedTime!.isAfter(now)) {
            NotificationShow().showNotification(
              todo.id,
              todo.name,
              todo.description,
              todo.todoCompletedTime,
            );
          }
        }
      }
      // No archive Task
      isar.writeTxnSync(() {
        task.archive = false;
        isar.tasks.putSync(task);
      });
      tasks.refresh();
      todos.refresh();
      EasyLoading.showSuccess('noCategoryArchive'.tr, duration: duration);
    }
  }

  // Todos
  Future<void> addTodo(Tasks task, String title, String desc, String time,
      bool pinned, Priority priority) async {
    try {
      DateTime? date;
      if (time.isNotEmpty) {
        // Adjust the date format to match the input format
        date =
            DateFormat("EEE, MMM d, yyyy HH:mm").parse(time); // Adjusted format
      }

      // Check for duplicates
      final existingTodo = isar.todos
          .filter()
          .nameEqualTo(title)
          .task((q) => q.idEqualTo(task.id))
          .todoCompletedTimeEqualTo(date)
          .findFirstSync();

      if (existingTodo != null) {
        throw Exception(
            "A todo with the same name and completion time exists.");
      }

      final newTodo = Todos(
        name: title,
        description: desc,
        todoCompletedTime: date,
        fix: pinned,
        createdTime: DateTime.now(),
        priority: priority,
      )..task.value = task;

      // Save to Isar
      await isar.writeTxn(() async {
        await isar.todos.put(newTodo);
        await newTodo.task.save();
      });

      todos.add(newTodo);

      // Save to Firestore
      await firestore.collection('todos').add({
        'name': title,
        'description': desc,
        'todoCompletedTime': date?.toIso8601String(),
        'taskId': task.firestoreId,
        'uid': currentUserId,
        'createdTime': DateTime.now().toIso8601String(),
        'priority': priority.name,
      });

      EasyLoading.showSuccess("Todo added successfully.");
    } catch (e) {
      print("Error adding todo: $e");
      EasyLoading.showError("Failed to add todo.");
    }
  }

  Future<void> updateTodoCheck(Todos todo) async {
    isar.writeTxnSync(() => isar.todos.putSync(todo));
    todos.refresh();
  }

  Future<void> updateTodo(Todos todo, Tasks task, String title, String desc,
      String time, bool pined, Priority priority) async {
    DateTime? date;
    if (time.isNotEmpty) {
      date = timeformat == '12'
          ? DateFormat.yMMMEd(locale.languageCode).add_jm().parse(time)
          : DateFormat.yMMMEd(locale.languageCode).add_Hm().parse(time);
    }
    isar.writeTxnSync(() {
      todo.name = title;
      todo.description = desc;
      todo.todoCompletedTime = date;
      todo.fix = pined;
      todo.priority = priority;
      todo.task.value = task;
      isar.todos.putSync(todo);
      todo.task.saveSync();
    });

    var newTodo = todo;
    int oldIdx = todos.indexOf(todo);
    todos[oldIdx] = newTodo;
    todos.refresh();

    if (date != null && now.isBefore(date)) {
      await flutterLocalNotificationsPlugin.cancel(todo.id);
      NotificationShow().showNotification(
        todo.id,
        todo.name,
        todo.description,
        date,
      );
    } else {
      await flutterLocalNotificationsPlugin.cancel(todo.id);
    }
    EasyLoading.showSuccess('updateTodo'.tr, duration: duration);
  }

  Future<void> transferTodos(List<Todos> todoList, Tasks task) async {
    List<Todos> todoListCopy = List.from(todoList);

    for (var todo in todoListCopy) {
      isar.writeTxnSync(() {
        todo.task.value = task;
        isar.todos.putSync(todo);
        todo.task.saveSync();
      });

      var newTodo = todo;
      int oldIdx = todos.indexOf(todo);
      todos[oldIdx] = newTodo;
    }

    todos.refresh();
    tasks.refresh();

    EasyLoading.showSuccess('updateTodo'.tr, duration: duration);
  }

  Future<void> deleteTodo(List<Todos> todoList) async {
    List<Todos> todoListCopy = List.from(todoList);

    for (var todo in todoListCopy) {
      if (todo.todoCompletedTime != null) {
        if (todo.todoCompletedTime!.isAfter(now)) {
          await flutterLocalNotificationsPlugin.cancel(todo.id);
        }
      }
      todos.remove(todo);
      isar.writeTxnSync(() => isar.todos.deleteSync(todo.id));
      EasyLoading.showSuccess('todoDelete'.tr, duration: duration);
    }
  }

  int createdAllTodos() {
    return todos.where((todo) => todo.task.value?.archive == false).length;
  }

  int completedAllTodos() {
    return todos
        .where((todo) => todo.task.value?.archive == false && todo.done == true)
        .length;
  }

  int createdAllTodosTask(Tasks task) {
    return todos.where((todo) => todo.task.value?.id == task.id).length;
  }

  int completedAllTodosTask(Tasks task) {
    return todos
        .where((todo) => todo.task.value?.id == task.id && todo.done == true)
        .length;
  }

  int countTotalTodosCalendar(DateTime date) {
    return todos
        .where((todo) =>
            todo.done == false &&
            todo.todoCompletedTime != null &&
            todo.task.value?.archive == false &&
            DateTime(date.year, date.month, date.day, 0, -1)
                .isBefore(todo.todoCompletedTime!) &&
            DateTime(date.year, date.month, date.day, 23, 60)
                .isAfter(todo.todoCompletedTime!))
        .length;
  }

  void doMultiSelectionTask(Tasks tasks) {
    if (isMultiSelectionTask.isTrue) {
      isPop.value = false;
      if (selectedTask.contains(tasks)) {
        selectedTask.remove(tasks);
      } else {
        selectedTask.add(tasks);
      }

      if (selectedTask.isEmpty) {
        isMultiSelectionTask.value = false;
        isPop.value = true;
      }
    }
  }

  void doMultiSelectionTaskClear() {
    selectedTask.clear();
    isMultiSelectionTask.value = false;
    isPop.value = true;
  }

  void doMultiSelectionTodo(Todos todos) {
    if (isMultiSelectionTodo.isTrue) {
      isPop.value = false;
      if (selectedTodo.contains(todos)) {
        selectedTodo.remove(todos);
      } else {
        selectedTodo.add(todos);
      }

      if (selectedTodo.isEmpty) {
        isMultiSelectionTodo.value = false;
        isPop.value = true;
      }
    }
  }

  void doMultiSelectionTodoClear() {
    selectedTodo.clear();
    isMultiSelectionTodo.value = false;
    isPop.value = true;
  }
}
