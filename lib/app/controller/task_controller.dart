import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class TaskController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final tasks = <Map<String, dynamic>>[].obs;

  /// Fetch tasks (categories) for the logged-in user
  Stream<List<Map<String, dynamic>>> fetchTasks(String uid) {
    return firestore
        .collection('tasks')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  /// Add a new task
  Future<void> addTask(String title, String desc, int color, String uid) async {
    try {
      await firestore.collection('tasks').add({
        'title': title,
        'description': desc,
        'taskColor': color,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      Get.snackbar("Success", "Task added successfully.");
    } catch (e) {
      Get.snackbar("Error", "Failed to add task: $e");
    }
  }

  /// Update an existing task
  Future<void> updateTask(
      String taskId, Map<String, dynamic> updatedData) async {
    try {
      await firestore.collection('tasks').doc(taskId).update(updatedData);
      Get.snackbar("Success", "Task updated successfully.");
    } catch (e) {
      Get.snackbar("Error", "Failed to update task: $e");
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    try {
      await firestore.collection('tasks').doc(taskId).delete();
      Get.snackbar("Success", "Task deleted successfully.");
    } catch (e) {
      Get.snackbar("Error", "Failed to delete task: $e");
    }
  }
}
