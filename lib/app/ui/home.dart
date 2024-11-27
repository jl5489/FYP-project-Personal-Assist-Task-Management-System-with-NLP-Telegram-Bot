import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:todark/app/ui/tasks/view/all_tasks.dart';
import 'package:todark/app/ui/settings/view/settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:todark/app/ui/tasks/widgets/tasks_action.dart';
import 'package:todark/app/ui/todos/view/calendar_todos.dart';
import 'package:todark/app/ui/todos/view/all_todos.dart';
import 'package:todark/app/ui/todos/widgets/todos_action.dart';
import 'package:todark/theme/theme_controller.dart';
import 'package:todark/app/controller/auth_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final themeController = Get.put(ThemeController());
  final AuthController _authController = Get.put(AuthController());

  int tabIndex = 0;

  final List<Widget> pages = const [
    AllTasks(), // Widget for the first tab - AllTasks
    AllTodos(), // Widget for the second tab - AllTodos
    CalendarTodos(), // Widget for the third tab - CalendarTodos
    SettingsPage(), // Widget for the fourth tab - SettingsPage
  ];

  /// Change tab index and rebuild the UI
  void changeTabIndex(int index) {
    setState(() {
      tabIndex = index;
    });
  }

  /// Show logout confirmation dialog
  Future<void> showLogoutConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('logout'.tr),
          content: Text('confirmLogout'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('logout'.tr),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _authController.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: showLogoutConfirmation,
          ),
        ],
      ),
      body: IndexedStack(
        index: tabIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) => changeTabIndex(index),
        selectedIndex: tabIndex,
        destinations: [
          NavigationDestination(
            icon: const Icon(IconsaxPlusLinear.folder_2),
            selectedIcon: const Icon(IconsaxPlusBold.folder_2),
            label: 'categories'.tr,
          ),
          NavigationDestination(
            icon: const Icon(IconsaxPlusLinear.task_square),
            selectedIcon: const Icon(IconsaxPlusBold.task_square),
            label: 'allTodos'.tr,
          ),
          NavigationDestination(
            icon: const Icon(IconsaxPlusLinear.calendar),
            selectedIcon: const Icon(IconsaxPlusBold.calendar),
            label: 'calendar'.tr,
          ),
          NavigationDestination(
            icon: const Icon(IconsaxPlusLinear.category),
            selectedIcon: const Icon(IconsaxPlusBold.category),
            label: 'settings'.tr,
          ),
        ],
      ),
      floatingActionButton: tabIndex == 3
          ? null
          : FloatingActionButton(
              onPressed: () {
                showModalBottomSheet(
                  enableDrag: false,
                  context: context,
                  isScrollControlled: true,
                  builder: (BuildContext context) {
                    return tabIndex == 0
                        ? TasksAction(
                            text: 'create'.tr,
                            edit: false,
                          )
                        : TodosAction(
                            text: 'create'.tr,
                            edit: false,
                            category: true,
                          );
                  },
                );
              },
              child: const Icon(IconsaxPlusLinear.add),
            ),
    );
  }
}
