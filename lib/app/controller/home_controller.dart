import 'package:get/get.dart';
import 'package:todark/app/controller/auth_controller.dart';

class HomeController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();

  // Observables for user-specific data
  var tasks = <Map<String, dynamic>>[].obs;
  var todos = <Map<String, dynamic>>[].obs;
  var notifications = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchUserData(); // Fetch user data on initialization
  }

  /// Fetch user data and update observable lists
  Future<void> fetchUserData() async {
    try {
      final user = _authController.user.value;
      if (user == null) {
        throw Exception("No logged-in user found.");
      }

      // Fetch tasks, todos, and notifications
      final userData = await _authController.fetchUserData(user.uid);

      // Update observables
      tasks.assignAll(userData['tasks'] ?? []);
      todos.assignAll(userData['todos'] ?? []);
      notifications.assignAll(userData['notifications'] ?? []);
      print("User data refreshed and assigned.");
    } catch (e) {
      print("Error in fetchUserData: $e");
      Get.snackbar("Error", "Failed to fetch user data.");
    }
  }

  /// Refresh all user-specific data (tasks, todos, notifications)
  Future<void> refreshData() async {
    await fetchUserData();
    print("User data refreshed.");
  }
}
