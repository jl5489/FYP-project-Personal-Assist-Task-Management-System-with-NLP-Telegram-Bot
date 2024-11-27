import sqlite3
import telebot
import spacy
from datetime import datetime, timedelta
from telebot import types
from dateutil.parser import parse
import threading
import time
import firebase_admin
from firebase_admin import credentials, firestore
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
from firebase_admin import exceptions as firebase_exceptions
from firebase_admin import credentials, firestore, auth, exceptions as firebase_exceptions
from threading import Lock


cred = credentials.Certificate("C:\\FlutterProject\\FYP\\Telegram\\todolist-f6c6d-firebase-adminsdk-pu7b6-971659b770.json")
firebase_admin.initialize_app(cred)
TOKEN = "7877361330:AAHSV-3tn2lVTpbmMYCClkDGY9MbwdS2hAM"
bot = telebot.TeleBot(TOKEN)
nlp = spacy.load("en_core_web_sm")
user_states = {}
db = firestore.client()
user_states_lock = Lock()
def safe_update_user_state(chat_id, key, value):
    with user_states_lock:
        if chat_id in user_states:
            user_states[chat_id][key] = value

# Priority Levels Mapping
PRIORITY_LEVELS = {
        '1': 'High',
        '2': 'Medium',
        '3': 'Low',
        '4': 'No Priority'
    }
REMINDER_TIMES = {
        '1': '1 hour',
        '2': '10 minutes',
        '3': '1 day',
        '4': 'on time'
    }
class UserSession:
    def __init__(self, chat_id, email=None, user_uid=None):
        self.chat_id = chat_id
        self.email = email
        self.user_uid = user_uid
        self.status = 'AWAITING_EMAIL'
        self.temp_data = {}
        self.last_activity = datetime.now()
    
    def update_status(self, new_status):
        self.status = new_status
        self.last_activity = datetime.now()
    
    def set_auth_data(self, email, user_uid):
        self.email = email
        self.user_uid = user_uid
        self.last_activity = datetime.now()
def debug_log(user_id, message):
    print(f"DEBUG [{user_id}]: {message}")
def debug_user_states(chat_id, location=""):
    """Prints the current state of user_states for a specific chat ID for debugging purposes."""
    if chat_id in user_states:
        print(f"DEBUG at {location}: user_states for chat_id {chat_id}: {user_states.get(chat_id, 'Not found')}")

    else:
        print(f"Debugging at {location}: No user state found for chat_id {chat_id}")
        

def handle_error(chat_id, message):
    bot.send_message(chat_id, message)



def fetch_user_data(user_uid):
    user_ref = db.collection('users').document(user_uid)
    user_doc = user_ref.get()
    return user_doc.to_dict() if user_doc.exists else None

def fetch_tasks(chat_id):
    """
    Fetch tasks using the Firebase user_uid from user_states
    """
    if chat_id not in user_states or 'user_uid' not in user_states[chat_id]:
        print(f"No user_uid found for chat_id {chat_id}")
        return []
    
    user_uid = user_states[chat_id]['user_uid']
    print(f"Fetching tasks for user_uid: {user_uid}")  # Debug log
    
    tasks_ref = db.collection('todos')
    tasks_query = tasks_ref.where('uid', '==', user_uid).stream()

    tasks = []
    for task in tasks_query:
        task_data = task.to_dict()
        tasks.append({
            'taskId': task.id,
            'title': task_data.get('title'),
            'description': task_data.get('description'),
            'priority': task_data.get('priority_level', 'None'),
            'due_date': task_data.get('dueDate'),
            'category_id': task_data.get('category_id', None),  # Ensure category_id is always included
            'completed': task_data.get('task_status') == 'completed'
        })
    
    print(f"Found {len(tasks)} tasks")  # Debug log
    return tasks

def schedule_notifications(task_id, user_id, description, due_datetime, reminder_time):
    """
    Schedule a notification for a task based on the updated due date and reminder time.
    """
    # Calculate the time delta for the reminder
    reminder_delta = parse_reminder_time(reminder_time)
    notification_time = due_datetime - reminder_delta

    # Ensure the user UID is present in the user state for Firestore operations
    if user_id not in user_states or 'user_uid' not in user_states[user_id]:
        print(f"Error: User UID missing for user_id {user_id}. Cannot schedule notification.")
        bot.send_message(user_id, "⚠️ Session expired. Please log in again using /start.")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return

    user_uid = user_states[user_id]['user_uid']
    notifications_ref = db.collection(u'notifications')

    # Create a new notification document in Firestore
    try:
        notifications_ref.add({
            u'uid': user_uid,
            u'taskId': task_id,
            u'title': 'Task Reminder',
            u'body': f'Reminder for task: {description}',
            u'scheduledTime': notification_time.isoformat(),
            u'createdAt': firestore.SERVER_TIMESTAMP,
            u'sent': False  # Track if the notification has been sent
        })

        # Schedule the reminder using threading.Timer if the scheduled time is in the future
        delay = (notification_time - datetime.now()).total_seconds()
        if delay > 0:
            threading.Timer(delay, send_notification, args=(user_id, description, due_datetime, reminder_time)).start()
            print(f"DEBUG: Scheduled reminder for task {task_id} at {notification_time}")
        else:
            print(f"DEBUG: Reminder time for task {task_id} has already passed.")
    except Exception as e:
        print(f"Error scheduling notification for user {user_id} with task {task_id}: {e}")

        
def fetch_notifications(user_id):
    notifications_ref = db.collection(u'notifications')
    query = notifications_ref.where(u'userId', u'==', user_id)
    notifications = query.stream()
    
    notification_list = []
    for notification in notifications:
        notification_data = notification.to_dict()
        notification_list.append({
            'id': notification.id,
            'title': notification_data.get('title', ''),
            'body': notification_data.get('body', ''),
            'scheduledTime': notification_data.get('scheduledTime', ''),
        })
    return notification_list

def list_notifications(user_id):
        notifications = fetch_notifications(user_id)
        if not notifications:
            bot.send_message(user_id, "No notifications found.")
        else:
            for notification in notifications:
                bot.send_message(user_id, f"Notification: {notification['title']}\nBody: {notification['body']}\nScheduled: {notification['scheduledTime']}")
def add_task_to_firestore(user_id, task_name, task_description, task_priority, due_date=None, reminder_time=None, category_id=None):
    """
    Add a task to Firestore with validation, and schedule notifications based on the task's due date and reminder time.
    """
    debug_log(user_id, f"Adding task: {task_name}")
    
    # Ensure the user is authenticated
    if user_id not in user_states or 'user_uid' not in user_states[user_id]:
        debug_log(user_id, "User not authenticated")
        return False, "Error: User is not authenticated. Please log in again."
    
    # Validate input
    if not task_name or not task_description:
        debug_log(user_id, "Invalid task data")
        return False, "Error: Task name and description are required."
    
    # Prepare task data for Firestore
    user_uid = user_states[user_id]['user_uid']
    task_data = {
        'uid': user_uid,
        'title': task_name.strip(),
        'description': task_description.strip(),
        'priority_level': task_priority,
        'createdAt': firestore.SERVER_TIMESTAMP,
        'task_status': 'not started',
        'reminder_time': reminder_time,  # Store reminder time as part of the task
    }
    
    # Add optional fields if provided
    if due_date:
        task_data['due_date'] = due_date.strftime('%Y-%m-%d %H:%M')
    if category_id:
        task_data['category_id'] = category_id

    try:
        # Add the task to Firestore
        tasks_ref = db.collection('todos')
        new_task_ref = tasks_ref.add(task_data)
        task_id = new_task_ref[1].id
        
        debug_log(user_id, f"Task added successfully with ID: {task_id}")
        
        # Schedule a notification if due_date and reminder_time are set
        if due_date and reminder_time:
            try:
                schedule_notifications(
                    task_id,
                    user_id,
                    task_description,
                    due_date,
                    reminder_time
                )
            except Exception as e:
                debug_log(user_id, f"Notification scheduling failed: {str(e)}")
                # Continue even if scheduling fails
        
        return True, task_id
        
    except firebase_exceptions.FirebaseError as e:
        debug_log(user_id, f"Firebase error: {str(e)}")
        return False, f"Database error: {str(e)}"
    except Exception as e:
        debug_log(user_id, f"Unexpected error: {str(e)}")
        return False, "An unexpected error occurred"


def add_notification_to_firestore(user_id, title, body, scheduled_time):
        notifications_ref = db.collection(u'notifications')
        notifications_ref.add({
            u'userId': user_id,
            u'title': title,
            u'body': body,
            u'scheduledTime': scheduled_time,
            u'createdAt': firestore.SERVER_TIMESTAMP
        })
        bot.send_message(user_id, f"Notification '{title}' added successfully!")

def delete_task_from_firestore(user_id, task_id):
        task_ref = db.collection(u'tasks').document(task_id)
        task_ref.delete()
        bot.send_message(user_id, f"Task '{task_id}' deleted successfully!")

# Function to extract both date and time using spaCy and dateutil
def extract_datetime_info(text):
        today = datetime.now()
        datetimes = []

        debug_log('SYSTEM', f"Parsing date from input: {text}")

        # Handle relative dates like 'tomorrow'
        if 'tomorrow' in text.lower():
            parsed_datetime = today + timedelta(days=1)
            datetimes.append(parsed_datetime)
            debug_log('SYSTEM', f"Parsed relative date: {parsed_datetime}")
        else:
            try:
                parsed_datetime = parse(text, fuzzy=True)
                datetimes.append(parsed_datetime)
                debug_log('SYSTEM', f"Parsed absolute date: {parsed_datetime}")
            except Exception as e:
                debug_log('SYSTEM', f"Error parsing date: {e}")
                return None  # Return None if parsing fails

        return datetimes

def handle_add_task_step(message, step):
    """
    Handle the multi-step task creation process with improved error handling and validation.
    """
    user_id = message.chat.id
    debug_log(user_id, f"Handling step {step} of task creation")
    if user_id not in user_states or 'user_uid' not in user_states[user_id]:
        bot.send_message(user_id, "⚠️ Please log in first using /start.")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return

    try:
        user_uid = user_states[user_id]['user_uid']  # Retrieve user_uid here for consistent use

        if step == 1:
            # Step 1: Ask for task name
            debug_log(user_id, "Asking for task name")
            bot.send_message(user_id, "📄 *Step 1: Task Name*\nPlease enter the task name.", parse_mode='Markdown')
            user_states[user_id].update({'status': "ADDING_TASK_STEP_2"})

        elif step == 2:
            # Step 2: Receive task name and ask for description
            task_name = message.text.strip()
            debug_log(user_id, f"Received task name: {task_name}")

            if not task_name:
                bot.send_message(user_id, "❌ Task name cannot be empty. Please enter a valid task name.")
                return
            else:
                user_states[user_id]['task_name'] = task_name
                bot.send_message(user_id, f"✅ Task name received: *'{task_name}'*\nNow, please enter the task description.", parse_mode='Markdown')
                user_states[user_id]['status'] = "ADDING_TASK_STEP_3"

        elif step == 3:
            # Step 3: Receive task description and ask for due date and time
            task_description = message.text.strip()
            debug_log(user_id, f"Received task description: {task_description}")

            if not task_description:
                bot.send_message(user_id, "❌ Task description cannot be empty. Please enter a valid description.")
                return
            else:
                # Store the task description and move to Step 4
                user_states[user_id].update({'description': task_description, 'status': "ADDING_TASK_STEP_4"})
                debug_log(user_id, "Moving to ADDING_TASK_STEP_4")
                
                # Ask for due date and time
                bot.send_message(user_id, "✅ Task description received! Now, please enter the due date and time (e.g., 'tomorrow at 14:00', '2023-12-25 09:00').", parse_mode='Markdown')

        elif step == 4:
            # Step 4: Receive due date and time
            due_datetime_text = message.text.strip()
            debug_log(user_id, f"Received due date text: {due_datetime_text}")

            due_datetimes = extract_datetime_info(due_datetime_text)
            if not due_datetimes:
                bot.send_message(user_id, "❌ I couldn't understand the due date and time. Please enter a valid date and time.")
                debug_log(user_id, f"Failed to parse due date from input: {due_datetime_text}")
                user_states[user_id]['status'] = "ADDING_TASK_STEP_4"  # Ensure we stay in this step
                return  # Stop further execution
            else:
                # Store due date(s) in user_states and proceed to priority
                user_states[user_id]['due_datetimes'] = due_datetimes
                user_states[user_id]['status'] = "ADDING_TASK_STEP_5"
                debug_log(user_id, f"Successfully parsed due date(s): {due_datetimes}")
                bot.send_message(user_id, "🔢 *Step 4: Priority*\nPlease enter the priority number:\n1. High\n2. Medium\n3. Low\n4. No Priority", parse_mode='Markdown')

        elif step == 5:
            priority_input = message.text.strip()
            user_id = message.chat.id

            # Check if user_uid exists in user_states
            if 'user_uid' not in user_states[user_id]:
                bot.send_message(user_id, "❌ User ID not found. Please start the process again.")
                debug_log(user_id, "User ID missing from user_states")
                user_states[user_id]['status'] = 'CHOOSING_ACTION'
                return

            # Assuming PRIORITY_LEVELS is a dictionary like { "1": "High", "2": "Medium", etc. }
            if priority_input not in PRIORITY_LEVELS:
                bot.send_message(user_id, "❌ Invalid priority number. Please enter a number between 1 and 4.")
                return

            user_states[user_id]['priority_level'] = PRIORITY_LEVELS[priority_input]

            try:
                # Fetch categories using `user_uid`
                user_uid = user_states[user_id]['user_uid']
                debug_log(user_id, f"Attempting to fetch categories for user_uid: {user_uid}")

                categories_ref = db.collection('tasks')
                categories_query = categories_ref.where('uid', '==', user_uid).stream()

                categories = []
                for category in categories_query:
                    category_data = category.to_dict()
                    categories.append({
                        'title': category_data.get('title'),
                        'description': category_data.get('description'),
                        'id': category.id
                    })
                
                if not categories:
                    bot.send_message(
                        user_id, 
                        "❌ No categories found. Please add a category first by typing /add_category"
                    )
                    user_states[user_id]['status'] = 'CHOOSING_ACTION'
                    return
                
                # Display categories to user
                category_options = "\n".join(
                    [f"{index + 1}. {cat['title']} - {cat['description']}" for index, cat in enumerate(categories)]
                )

                bot.send_message(
                    user_id,
                    f"🔢 *Step 5: Select a Category*\n"
                    f"Please choose a category by typing its number:\n{category_options}",
                    parse_mode='Markdown'
                )

                # Store the categories list in user_states to map the selected number to the category ID
                user_states[user_id]['categories'] = categories
                user_states[user_id]['status'] = 'ADDING_TASK_STEP_6'
            
            except Exception as e:
                debug_log(user_id, f"Error in fetching categories: {str(e)}")
                bot.send_message(
                    user_id,
                    "❌ An error occurred while fetching categories. Please try again or contact support."
                )
                user_states[user_id]['status'] = 'CHOOSING_ACTION'

        elif step == 6:
            category_number = message.text.strip()

            # Check if the input is a valid number within the range of categories
            if not category_number.isdigit() or int(category_number) < 1 or int(category_number) > len(user_states[user_id]['categories']):
                bot.send_message(user_id, "❌ Invalid category number. Please enter a valid number.")
                return

            # Map the selected number to the actual category ID
            category_index = int(category_number) - 1
            selected_category = user_states[user_id]['categories'][category_index]
            user_states[user_id]['category_id'] = selected_category['id']
            user_states[user_id]['status'] = "ADDING_TASK_STEP_7"

            # Prompt for reminder time
            bot.send_message(
                user_id,
                "⏰ *Step 6: Reminder Time*\nPlease choose when you'd like to be reminded:\n1. 1 hour before\n2. 10 minutes before\n3. 1 day before\n4. On the due time",
                parse_mode='Markdown'
            )

        elif step == 7:
            reminder_input = message.text.strip()
            
            # Validate the reminder input
            if reminder_input not in REMINDER_TIMES:
                bot.send_message(user_id, "❌ Invalid reminder option. Please enter a valid number (1-4).")
                return
            
            # Save the reminder time in user_states
            user_states[user_id]['reminder_time'] = REMINDER_TIMES[reminder_input]

            # Now proceed with creating the task
            task_name = user_states[user_id]['task_name']
            description = user_states[user_id]['description']
            due_datetimes = user_states[user_id]['due_datetimes']
            priority_level = user_states[user_id]['priority_level']
            reminder_time = user_states[user_id].get('reminder_time', "1 hour")  # Default to '1 hour' if not set
            selected_category = user_states[user_id].get('category_id', "Uncategorized")

            # Create the task and schedule notifications
            for due_datetime in due_datetimes:
                task_id = add_task(user_id, task_name, description, due_datetime, priority_level, reminder_time, selected_category)
                if task_id:  # Only schedule notifications if the task was successfully added
                    schedule_notifications(task_id, user_id, description, due_datetime, reminder_time)

            # Prepare confirmation message
            confirmation_message = (
                f"✅ Task created successfully!\n\n"
                f"*Task Details:*\n"
                f"- **Name**: {task_name}\n"
                f"- **Description**: {description}\n"
                f"- **Due Date**: {due_datetimes[0].strftime('%Y-%m-%d %H:%M')}\n"
                f"- **Priority**: {priority_level}\n"
                f"- **Category**: {selected_category}\n"
                f"- **Reminder**: {reminder_time}"
            )
            bot.send_message(user_id, confirmation_message, parse_mode='Markdown')

            # Reset user state for further actions
            user_states[user_id] = {
                'status': 'CHOOSING_ACTION',
                'user_uid': user_states[user_id]['user_uid']
            }
            send_welcome_message(user_id)
            debug_log(user_id, "Task creation completed.")
    except Exception as e:
        debug_log(user_id, f"Error occurred: {e}")
        bot.send_message(user_id, "❌ An error occurred while processing your request. Please try again.")



@bot.message_handler(commands=['add_category'])
def add_category(message):
    chat_id = message.chat.id
    if chat_id not in user_states or 'user_uid' not in user_states[chat_id]:
        bot.send_message(chat_id, "Please log in first using /start")
        return
    
    user_states[chat_id]['status'] = 'ADDING_CATEGORY_NAME'
    bot.send_message(chat_id, "Please enter the category name.")

def add_category_to_firestore(chat_id, category_name, category_description, user_uid):
    try:
        categories_ref = db.collection(u'tasks')
        categories_ref.add({
            u'uid': user_uid,
            u'title': category_name,
            u'description': category_description,
            u'createdAt': firestore.SERVER_TIMESTAMP,
            u'taskColor': "4280391411"
        })
        bot.send_message(chat_id, f"✅ Category '{category_name}' added successfully!")
        print(f"Category '{category_name}' added for user_uid {user_uid}")
    except Exception as e:
        bot.send_message(chat_id, f"Error adding category: {str(e)}")
        print(f"Error adding category: {str(e)}")

def fetch_categories(chat_id):
    """
    Fetch categories using the Firebase user_uid from user_states
    """
    if chat_id not in user_states or 'user_uid' not in user_states[chat_id]:
        print(f"No user_uid found for chat_id {chat_id}")
        return {}
    
    user_uid = user_states[chat_id]['user_uid']
    print(f"Fetching categories for user_uid: {user_uid}")  # Debug log
    
    categories_ref = db.collection('tasks')
    categories_query = categories_ref.where('uid', '==', user_uid).stream()

    # Using a dictionary to map category_id to title for easier lookup
    categories = {category.id: category.to_dict().get('title', 'Uncategorized') for category in categories_query}
    
    print(f"Found {len(categories)} categories")  # Debug log
    return categories  # Ensure this is a dictionary


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'ADDING_CATEGORY_DESCRIPTION')
def handle_category_description(message):
    chat_id = message.chat.id
    category_description = message.text.strip()
    
    if chat_id not in user_states or 'user_uid' not in user_states[chat_id]:
        bot.send_message(chat_id, "Error: User authentication required. Please /start again.")
        return
    
    current_state = user_states[chat_id]
    category_name = current_state.get('category_name')
    user_uid = current_state.get('user_uid')
    
    if not category_name or not user_uid:
        bot.send_message(chat_id, "Error: Missing category information. Please try again.")
        return
    
    # Add category to Firestore
    add_category_to_firestore(chat_id, category_name, category_description, user_uid)
    
    # Update status while preserving user_uid
    user_states[chat_id] = {
        'status': 'CHOOSING_ACTION',
        'user_uid': user_uid
    }
    
    # Send welcome message with updated categories
    send_welcome_message(chat_id)

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'ADDING_CATEGORY_NAME')
def handle_category_name(message):
    chat_id = message.chat.id
    category_name = message.text.strip()
    
    if 'user_uid' not in user_states[chat_id]:
        bot.send_message(chat_id, "Error: User authentication required. Please /start again.")
        return
    
    # Store category name and update status while preserving user_uid
    current_state = user_states[chat_id]
    user_states[chat_id] = {
        'status': 'ADDING_CATEGORY_DESCRIPTION',
        'category_name': category_name,
        'user_uid': current_state['user_uid']
    }
    
    bot.send_message(chat_id, "Please enter the category description.")

def handle_add_task_step_category(message):
    """
    Handle the category selection step when adding a new task.
    Validates priority input and presents available categories to the user.
    """
    user_id = message.chat.id
    debug_log(user_id, f"[Category Step]: Current user_states for {user_id}: {user_states.get(user_id, {})}")

    # Check if user is authenticated and has a valid user_uid
    if 'user_uid' not in user_states.get(user_id, {}):
        bot.send_message(user_id, "⚠️ Session expired. Please login again using /start.")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return

    priority_input = message.text.strip()

    # Validate priority input
    if priority_input not in PRIORITY_LEVELS:
        bot.send_message(user_id, "❌ Invalid priority number. Please enter a number between 1 and 4.")
        return

    # Save priority level in user state
    user_states[user_id]['priority_level'] = PRIORITY_LEVELS[priority_input]

    try:
        
        user_uid = user_states[user_id]['user_uid']
        categories_ref = db.collection('tasks')
        categories_query = categories_ref.where('uid', '==', user_uid).stream()

        categories_list = []
        for category in categories_query:
            category_data = category.to_dict()
            categories_list.append({
                'id': category.id,
                'title': category_data.get('title'),
                'description': category_data.get('description')
            })

        if not categories_list:
            bot.send_message(
                user_id, 
                "❌ No categories found. Please add a category first by typing /add_category"
            )
            user_states[user_id]['status'] = 'CHOOSING_ACTION'
            return

        # Format categories for display
        category_options = []
        for category in categories_list:
            category_line = f"{category['id']}: {category['title']}"
            if category['description']:
                category_line += f" - {category['description']}"
            category_options.append(category_line)

        formatted_categories = "\n".join(category_options)

        # Send categories list to user
        bot.send_message(
            user_id,
            f"🔢 *Step 5: Select a Category*\n"
            f"Please choose a category by typing its ID:\n"
            f"{formatted_categories}",
            parse_mode='Markdown'
        )

        # Update user state to proceed to next step
        user_states[user_id]['status'] = 'ADDING_TASK_STEP_6'

    except Exception as e:
        debug_log(user_id, f"Error in category selection: {str(e)}")
        bot.send_message(
            user_id,
            "❌ An error occurred while fetching categories. Please try again or contact support."
        )
        user_states[user_id]['status'] = 'CHOOSING_ACTION'

def handle_task_category_selection(message):
    """
    Handle the user's category selection and proceed to reminder time selection.
    """
    user_id = message.chat.id
    debug_log(user_id, f"[Category Selection]: Processing category selection for user {user_id}")
    
    # Check if user is authenticated
    if 'user_uid' not in user_states.get(user_id, {}):
        bot.send_message(user_id, "⚠️ Session expired. Please login again using /start")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return
    
    category_id = message.text.strip()
    user_uid = user_states[user_id]['user_uid']

    try:
        # Verify category exists and belongs to user
        category_ref = db.collection('tasks').document(category_id)
        category = category_ref.get()
        
        if not category.exists:
            bot.send_message(user_id, "❌ Invalid category ID. Please try again.")
            return
            
        category_data = category.to_dict()
        if category_data.get('uid') != user_uid:
            bot.send_message(user_id, "❌ You don't have access to this category.")
            return
            
        # Store category selection and proceed
        user_states[user_id]['category_id'] = category_id
        user_states[user_id]['status'] = "ADDING_TASK_STEP_7"
        
        # Define reminder options
        reminder_message = (
            "⏰ *Step 6: Reminder Time*\n"
            "Please choose when you'd like to be reminded:\n"
            "1. 1 hour before\n"
            "2. 10 minutes before\n"
            "3. 1 day before\n"
            "4. On the due time"
        )
        
        bot.send_message(
            user_id,
            reminder_message,
            parse_mode='Markdown'
        )
        
    except Exception as e:
        debug_log(user_id, f"Error in category selection validation: {str(e)}")
        bot.send_message(
            user_id,
            "❌ An error occurred while processing your selection. Please try again."
        )

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'DELETE_TASK_CHOOSE_ID')
def handle_delete_task(message):
    user_id = message.chat.id
    task_id = message.text.strip()

    # Call the delete task function
    delete_task(user_id, task_id)

    # Confirm deletion and return to main menu
    bot.send_message(user_id, f"Task '{task_id}' successfully deleted.")
    send_welcome_message(user_id)
    user_states[user_id]['status'] = 'CHOOSING_ACTION'




def send_notification(user_id, description, due_datetime, reminder_time):
        # Customize the message sent to the user
        message = (f"⏰ *Reminder!* You have an upcoming task:\n"
                f"📌 *Task*: {description}\n"
                f"📅 *Due Date*: {due_datetime.strftime('%Y-%m-%d %H:%M')}\n"
                f"⏰ *Reminder*: {reminder_time} before the due date.")
        
        # Send the message to the user via the bot
        bot.send_message(user_id, message, parse_mode='Markdown')

        # Log for debugging purposes
        print(f"DEBUG: Notification sent to user {user_id} for task '{description}'")

@bot.message_handler(commands=['start'])
def start(message):
    chat_id = message.chat.id
    user_states[chat_id] = {
        'status': 'AWAITING_EMAIL',
        'user_uid': None  # Initially set user_uid as None
    }
    bot.send_message(chat_id, "Welcome! Please enter your Gmail address to log in.")


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'AWAITING_EMAIL')
def handle_email(message):
    chat_id = message.chat.id
    email = message.text.strip()
    
    if '@' in email and '.' in email:
        user_states[chat_id] = {
            'status': 'AWAITING_PASSWORD',
            'email': email
        }
        bot.send_message(chat_id, "Please enter your password.")
    else:
        bot.send_message(chat_id, "Invalid email format. Please try again.")

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'AWAITING_PASSWORD')
def handle_password(message):
    chat_id = message.chat.id
    email = user_states[chat_id]['email']
    
    try:
        user = auth.get_user_by_email(email)
        user_uid = user.uid  # Extract the user UID from the authenticated user

        # Store user state and email
        user_states[chat_id] = {
            'status': 'CHOOSING_ACTION',
            'user_uid': user_uid,
            'email': email
        }
        
        # Create or update the mapping between user_uid and telegram_chat_id
        create_user_mapping(user_uid, chat_id)
        
        bot.send_message(chat_id, "Authentication successful!")
        send_welcome_message(chat_id)
        user_states[chat_id]['status'] = 'CHOOSING_ACTION'

    except auth.UserNotFoundError:
        bot.send_message(chat_id, "User not found. Please register first.")
        user_states[chat_id] = {'status': 'AWAITING_EMAIL'}
    except Exception as e:
        bot.send_message(chat_id, f"An error occurred: {str(e)}")
        user_states[chat_id] = {'status': 'AWAITING_EMAIL'}


def send_welcome_message(chat_id):
    """
    Send welcome message with categories and todos
    """
    # Check if user is authenticated
    if chat_id not in user_states or 'user_uid' not in user_states[chat_id]:
        bot.send_message(chat_id, "Please log in first using /start")
        return
    
    user_uid = user_states[chat_id].get('user_uid')
    if not user_uid:
        bot.send_message(chat_id, "Session expired. Please log in again.")
        user_states[chat_id] = {'status': 'AWAITING_EMAIL'}
        return
    
    user_states[chat_id]['status'] = 'CHOOSING_ACTION'    
    # Fetch user's categories and todos
    categories = fetch_categories(chat_id)  # Dictionary of category_id to title
    todos = fetch_tasks(chat_id)
    
    # Build the categories section
    if not categories:
        categories_message = "📁 No categories found."
    else:
        categories_message = "🗂️ Your Categories:\n"
        for category_name in categories.values():
            categories_message += f"- {category_name}\n"

    # Build the todos section
    if not todos:
        todos_message = "📝 No todos found."
    else:
        todos_message = "📋 Your Todos:\n"
        for todo in todos:
            priority = todo.get('priority', 'None')
            category_name = categories.get(todo.get('category_id'), "Uncategorized")
            todos_message += f"- {todo['title']} (Priority: {priority}, Category: {category_name})\n"

    # Debug information
    print(f"Sending welcome message for user_uid: {user_uid}")
    print(f"Categories count: {len(categories)}")
    print(f"Todos count: {len(todos)}")

    # Construct the final welcome message
    welcome_text = (
        f"👋 Welcome to your Task Manager!\n\n"
        f"{categories_message}\n"
        f"{todos_message}\n\n"
        "Please choose an action by typing the corresponding number:\n"
        "1. Create Category\n"
        "2. Add Task\n"
        "3. List Tasks (Today or Upcoming Week)\n"
    )

    # Send the message to the user
    user_states[chat_id]['status'] = 'CHOOSING_ACTION'

    bot.send_message(chat_id, welcome_text)

# Add this helper function to debug user states
def print_user_state(chat_id, location):
    """
    Helper function to print current user state
    """
    state = user_states.get(chat_id, {})
    print(f"\nUser State at {location}:")
    print(f"Chat ID: {chat_id}")
    print(f"State: {state}")
    print(f"UID: {state.get('user_uid', 'Not found')}")
    print("------------------------")

def add_task(user_id, task_name, description, due_datetime, priority, reminder_time, category_id, task_status='not started'):
        user_uid = user_states[user_id]['user_uid']
        todos_ref = db.collection(u'todos')  # Storing tasks in the 'todos' collection
        
        # Check if a task with the same name and due date already exists
        query = todos_ref.where(u'uid', u'==', user_uid).where(u'title', u'==', task_name).where(u'due_date', u'==', due_datetime.strftime('%Y-%m-%d %H:%M'))
        existing_task = query.get()

        if not existing_task:
            # Add task to the 'todos' collection, include the selected category (from the 'tasks' collection)
            task_data = {
                u'uid': user_uid,
                u'title': task_name,
                u'description': description,
                u'due_date': due_datetime.strftime('%Y-%m-%d %H:%M'),
                u'priority_level': priority,
                u'reminder_time': reminder_time,
                u'category_id': category_id,  # Store the selected category
                u'task_status': task_status,
                u'createdAt': firestore.SERVER_TIMESTAMP
            }
            task_ref = todos_ref.add(task_data)  # Add to the 'todos' collection
            return task_ref[1].id  # Return Firestore document ID as task ID
        else:
            # Task already exists
            return None

def schedule_notifications(task_id, user_id, description, due_datetime, reminder_time):
    # Check if `user_uid` is present in user_states to retrieve UID for Firestore
    if user_id not in user_states or 'user_uid' not in user_states[user_id]:
        print(f"Error: User UID missing for user_id {user_id}. Cannot schedule notification.")
        bot.send_message(user_id, "⚠️ Session expired. Please log in again using /start.")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return

    user_uid = user_states[user_id]['user_uid']
    notifications_ref = db.collection(u'notifications')
    
    # Calculate the reminder delta (time before the due date to send the reminder)
    reminder_delta = parse_reminder_time(reminder_time)
    notification_time = due_datetime - reminder_delta

    try:
        # Save the reminder in the Firestore notifications collection
        notifications_ref.add({
            u'uid': user_uid,
            u'taskId': task_id,
            u'title': 'Task Reminder',
            u'body': f'Reminder for task: {description}',
            u'scheduledTime': notification_time.isoformat(),
            u'createdAt': firestore.SERVER_TIMESTAMP,
            u'sent': False  # Track if the notification has been sent
        })

        # Schedule the reminder with threading.Timer
        delay = (notification_time - datetime.now()).total_seconds()
        if delay > 0:
            threading.Timer(delay, send_notification, args=(user_id, description, due_datetime, reminder_time)).start()
            print(f"DEBUG: Scheduled reminder for task {task_id} at {notification_time}")
        else:
            print(f"DEBUG: Reminder time for task {task_id} has already passed.")
    except Exception as e:
        print(f"Error scheduling notification for user {user_id} with task {task_id}: {e}")



def check_and_send_notifications():
    while True:
        now = datetime.utcnow()

        # Query notifications where scheduledTime <= now and sent is False
        notifications_ref = db.collection('notifications')
        query = notifications_ref.where('scheduledTime', '<=', now.isoformat()).where('sent', '==', False)
        notifications_to_send = query.stream()

        for notification in notifications_to_send:
            notification_data = notification.to_dict()
            
            # Retrieve user_uid and task description from notification data
            user_uid = notification_data.get('uid')
            task_description = notification_data.get('body', "No description provided.")
            
            # Retrieve Telegram chat ID (user_id) based on user_uid
            # Assuming you have a mapping of user_uid to Telegram chat ID (user_id)
            user_id = get_telegram_chat_id(user_uid)
            
            if not user_id:
                print(f"DEBUG: No Telegram chat ID found for user_uid: {user_uid}")
                continue

            try:
                # Send the notification to the user
                bot.send_message(user_id, f"⏰ Reminder: {task_description}")
                print(f"DEBUG: Sent reminder to user {user_id} for task: {task_description}")

                # Mark the notification as sent in Firestore
                notifications_ref.document(notification.id).update({'sent': True})
            
            except Exception as e:
                print(f"Error sending notification to user {user_id}: {e}")
        
        # Wait a minute before checking again
        time.sleep(60)

def get_telegram_chat_id(user_uid):
    try:
        # Access the document for the given user_uid
        user_mapping_ref = db.collection('user_mappings').document(user_uid)
        user_mapping = user_mapping_ref.get()
        
        if user_mapping.exists:
            telegram_chat_id = user_mapping.to_dict().get('telegram_chat_id')
            if telegram_chat_id:
                return telegram_chat_id
            else:
                print(f"DEBUG: 'telegram_chat_id' field missing in document for user_uid {user_uid}")
        else:
            print(f"DEBUG: No document found in 'user_mappings' for user_uid {user_uid}")

    except Exception as e:
        print(f"Error retrieving Telegram chat ID for user_uid {user_uid}: {e}")
    
    print(f"Warning: No Telegram chat ID found for user_uid {user_uid}")
    return None

def create_user_mapping(user_uid, telegram_chat_id):
    """
    Create or update a mapping between user_uid and telegram_chat_id in Firestore.
    """
    try:
        db.collection('user_mappings').document(user_uid).set({
            'telegram_chat_id': telegram_chat_id
        })
        print(f"DEBUG: Created/Updated user mapping for user_uid {user_uid} with chat ID {telegram_chat_id}")
    except Exception as e:
        print(f"Error creating user mapping for user_uid {user_uid}: {e}")

    # Function to parse reminder time
def parse_reminder_time(reminder_text):
        if 'day' in reminder_text:
            return timedelta(days=1)
        elif 'hour' in reminder_text:
            return timedelta(hours=int(reminder_text.split()[0]))  # e.g., '1 hour'
        elif 'minute' in reminder_text:
            return timedelta(minutes=int(reminder_text.split()[0]))  # e.g., '10 minutes'
        elif 'on time' in reminder_text:
            return timedelta(seconds=0)  # Send the notification exactly at the due time
        else:
            return timedelta(hours=1)  # Default reminder time
    # Handle task filtering (e.g., 'today', 'category', or 'ALL')

def handle_task_list_type_selection(message):
    user_id = message.chat.id
    text = message.text.strip().lower()

    debug_log(user_id, f"User selected task list type: {text}")

    # Ensure only one call to list_tasks and display_tasks is made
    if text == 'today':
        tasks = list_tasks(user_id, 'today')
        user_states[user_id]['status'] = 'TASK_ACTION_MENU'
    elif text == 'all':
        tasks = list_tasks(user_id, 'all')
        user_states[user_id]['status'] = 'TASK_ACTION_MENU'
    elif text == 'completed':
        tasks = list_tasks(user_id, 'completed')
        user_states[user_id]['status'] = 'TASK_ACTION_MENU'
    elif text == 'category':
        # Fetch categories for the user
        categories = fetch_categories(user_id)

        # Check if categories exist
        if not categories:
            bot.send_message(user_id, "No categories found. Please add a category first by typing /add_category.")
            user_states[user_id]['status'] = 'CHOOSING_ACTION'
            return

        # Format category options for display
        category_options = "\n".join(
            [f"{index + 1}. {category_name} - {categories[category_id]}"
             for index, (category_id, category_name) in enumerate(categories.items())]
        )

        # Send categories for user selection
        bot.send_message(
            user_id,
            f"🔢 *Choose a Category*\nPlease select a category by typing its number:\n{category_options}",
            parse_mode='Markdown'
        )

        # Save categories to user state to map the selected number to the category ID
        user_states[user_id]['category_list'] = list(categories.items())
        user_states[user_id]['status'] = 'LISTING_TASKS_CATEGORY'
        debug_log(user_id, "Waiting for user to select a category number.")
    else:
        bot.send_message(user_id, "❌ Invalid option. Please type 'today', 'category', 'all', or 'completed'.")

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'LISTING_TASKS_CATEGORY')
def handle_list_tasks_category(message):
    user_id = message.chat.id
    category_number = message.text.strip()

    # Validate category number
    if not category_number.isdigit():
        bot.send_message(user_id, "❌ Invalid category number. Please enter a number from the list.")
        return

    category_index = int(category_number) - 1
    # Ensure the selected number is within range
    if category_index < 0 or category_index >= len(user_states[user_id]['category_list']):
        bot.send_message(user_id, "❌ Invalid category number. Please enter a valid number.")
        return

    # Get the category ID from the selected tuple
    selected_category_id, selected_category_title = user_states[user_id]['category_list'][category_index]
    
    # Fetch tasks for the chosen category and display them
    tasks = list_tasks(user_id, 'category', selected_category_id)

    # Reset the status after displaying tasks to prevent redundant calls
    user_states[user_id]['status'] = 'CHOOSING_ACTION'


def list_tasks(user_id, task_type, category_id=None):
    user_uid = user_states[user_id]['user_uid']
    todos_ref = db.collection(u'todos')
    today = datetime.now().date()  # Use date only to compare (avoid time part)

    # Start a basic query for the user's tasks
    query = todos_ref.where(u'uid', u'==', user_uid)
    debug_log(user_id, f"Starting task query for user_uid {user_uid} with task type '{task_type}'.")

    # Apply filtering by task type
    if task_type == 'today':
        start_of_today = today.strftime('%Y-%m-%d')
        end_of_today = (today + timedelta(days=1)).strftime('%Y-%m-%d')
        query = query.where(u'due_date', u'>=', start_of_today).where(u'due_date', u'<', end_of_today)
        query = query.where('task_status', '!=', 'completed')
        debug_log(user_id, "Filtering tasks for 'today'.")
    elif task_type == 'category' and category_id:
        query = query.where(u'category_id', u'==', category_id)
        query = query.where('task_status', '!=', 'completed')
        debug_log(user_id, f"Filtering tasks for category ID: {category_id}")
    elif task_type == 'all':
        query = query.where('task_status', '!=', 'completed')
        debug_log(user_id, "Filtering for all incomplete tasks.")
    elif task_type == 'completed':
        query = query.where(u'task_status', u'==', 'completed')  # Only show completed tasks
        debug_log(user_id, "Filtering for all completed tasks.")

    # Fetch tasks based on the constructed query
    try:
        tasks = query.stream()
        task_list = []
        for task in tasks:
            task_data = task.to_dict()
            task_list.append({
                'id': task.id,
                'title': task_data.get('title', 'No Title'),
                'description': task_data.get('description', 'No description available'),
                'due_date': task_data.get('due_date', 'No Due Date'),
                'priority': task_data.get('priority_level', 'Priority not set'),
                'category_id': task_data.get('category_id', None),
                'task_status': task_data.get('task_status') == 'completed'
            })

        debug_log(user_id, f"Retrieved {len(task_list)} tasks for display.")
        display_tasks(user_id, task_list)  # Ensure display_tasks is only called here

        return task_list  # Return the list to be displayed by display_tasks function
    except Exception as e:
        debug_log(user_id, f"Error fetching tasks: {e}")
        return []

    
# Function to handle the callback when the "Mark as Done" button is pressed
@bot.callback_query_handler(func=lambda call: call.data.startswith("mark_done"))
def handle_mark_done(call):
    user_id = call.message.chat.id
    task_id = call.data.split(":")[1]  # Extract the task ID from callback data

    # Update the task's status to "completed" in Firestore
    try:
        task_ref = db.collection(u'todos').document(task_id)
        task_ref.update({
            u'task_status': 'completed'
        })

        # Cancel or update any pending notifications related to this task
        cancel_notifications_for_task(task_id)

        # Notify the user of the successful update
        bot.answer_callback_query(call.id, "Task marked as done!")
        bot.edit_message_text(
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            text="✅ Task marked as done!"
        )
    except Exception as e:
        print(f"Error updating task {task_id} for user {user_id}: {e}")
        bot.answer_callback_query(call.id, "Failed to mark task as done. Please try again.")

# Function to cancel notifications for a specific task
def cancel_notifications_for_task(task_id):
    """
    Mark all unsent notifications for a specific task as 'sent' to cancel them.
    """
    notifications_ref = db.collection(u'notifications')
    query = notifications_ref.where(u'taskId', u'==', task_id).where(u'sent', u'==', False)
    notifications_to_cancel = query.stream()

    for notification in notifications_to_cancel:
        notification_ref = notifications_ref.document(notification.id)
        try:
            # Update the 'sent' status to True to cancel the notification
            notification_ref.update({
                u'sent': True
            })
            print(f"Canceled notification for task ID: {task_id}")
        except Exception as e:
            print(f"Error canceling notification for task {task_id}: {e}")


def display_tasks(user_id, tasks):
    """
    Display tasks to the user with options to mark as done, edit, or delete each task.
    """
    categories = fetch_categories(user_id)
    
    if not tasks:
        bot.send_message(user_id, "No tasks found.")
    else:
        for task in tasks:
            task_title = task.get('title', 'No Title')
            completed_status = "✅ Completed" if task.get('task_status') == 'completed' else "❌ Not Completed"
            category_name = categories.get(task.get('category_id'), "Uncategorized")
            due_date = task.get('due_date', 'No Due Date')
            priority = task.get('priority_level', 'Priority not set')
            
            response = (f"📌 Task: {task_title}\n"
                        f"🗂️ Category: {category_name}\n"
                        f"📅 Due: {due_date}\n"
                        f"🔢 Priority: {priority}\n"
                        f"{completed_status}\n\n")
            
            # Inline keyboard with buttons for "Mark as Done", "Edit", and "Delete"
            markup = InlineKeyboardMarkup()
            done_button = InlineKeyboardButton("Mark as Done", callback_data=f"mark_done:{task['id']}")
            edit_button = InlineKeyboardButton("Edit Task", callback_data=f"edit_task:{task['id']}")
            delete_button = InlineKeyboardButton("Delete Task", callback_data=f"delete_task:{task['id']}")
            markup.add(done_button, edit_button, delete_button)

            bot.send_message(user_id, response, reply_markup=markup)

    # After displaying tasks, prompt for the next action (option to go back to the main menu)
    bot.send_message(
        user_id,
        "What would you like to do next?\n"
        "1. Back to Main Menu",
    )
    user_states[user_id]['status'] = 'TASK_ACTION_MENU'

@bot.callback_query_handler(func=lambda call: call.data.startswith("edit_task"))
def handle_edit_task_callback(call):
    """
    Handle the callback when the "Edit Task" button is pressed.
    """
    user_id = call.message.chat.id
    task_id = call.data.split(":")[1]  # Extract task ID from callback data
    
    # Store the task ID and initiate editing by asking for the new title
    user_states[user_id] = {
        'status': 'EDITING_TASK_STEP_1',
        'task_id': task_id,
        'new_task': {}
    }
    bot.send_message(user_id, "Please enter the new title for the task.")

@bot.callback_query_handler(func=lambda call: call.data.startswith("delete_task"))
def handle_delete_task_callback(call):
    """
    Handle the callback when the "Delete Task" button is pressed.
    """
    user_id = call.message.chat.id
    task_id = call.data.split(":")[1]  # Extract task ID from callback data

    # Confirm task deletion
    bot.send_message(user_id, f"Are you sure you want to delete the task? Type 'yes' to confirm or 'no' to cancel.")
    user_states[user_id]['status'] = 'CONFIRM_DELETE_TASK'
    user_states[user_id]['task_id'] = task_id


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'CONFIRM_DELETE_TASK')
def handle_confirm_delete_task(message):
    user_id = message.chat.id
    if message.text.lower() == 'yes':
        task_id = user_states[user_id]['task_id']
        delete_task(user_id, task_id)
        bot.send_message(user_id, "✅ Task successfully deleted!")
    else:
        bot.send_message(user_id, "❌ Task deletion canceled.")
    
    # Return to the main menu
    send_welcome_message(user_id)
    user_states[user_id]['status'] = 'CHOOSING_ACTION'


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'TASK_ACTION_MENU')
def handle_task_action_menu(message):
    """
    Handle task action menu choices, allowing the user to return to the main menu.
    """
    user_id = message.chat.id
    text = message.text.strip().lower()

    if text == '1':  # Back to Main Menu
        send_welcome_message(user_id)
        user_states[user_id]['status'] = 'CHOOSING_ACTION'
    else:
        bot.send_message(user_id, "❌ Invalid option. Please type '1' to go back to the main menu.")

@bot.message_handler(func=lambda message: True)
def handle_user_input(message):
    user_id = message.chat.id
    text = message.text.strip().lower()
    current_state = user_states.get(user_id, {}).get('status', 'CHOOSING_ACTION')
    
    print(f"DEBUG: Current state for user {user_id}: {current_state}")  # Debugging

    # Handle choosing action (initial state)
    if current_state == "CHOOSING_ACTION":
        if text == '1':
            add_category(message)  # Handles creating a new category
        elif text == '2':
            handle_add_task_step(message, step=1)  # Handles adding a task
        elif text == '3':
            ask_task_list_type(user_id)  # Handles listing tasks
        else:
            bot.send_message(user_id, "❌ Invalid choice. Please type 1 to create a category, 2 to add a task, or 3 to list tasks.")
    
    # Handle task creation steps (Step 2 to Step 7)
    elif current_state == "ADDING_TASK_STEP_2":
        handle_add_task_step(message, step=2)
    elif current_state == "ADDING_TASK_STEP_3":
        handle_add_task_step(message, step=3)
    elif current_state == "ADDING_TASK_STEP_4":
        handle_add_task_step(message, step=4)
    elif current_state == "ADDING_TASK_STEP_5":
        handle_add_task_step(message, step=5)
    elif current_state == "ADDING_TASK_STEP_6":
        handle_add_task_step(message, step=6)
    elif current_state == "ADDING_TASK_STEP_7":
        handle_add_task_step(message, step=7)

    # Handle task filtering
    elif current_state == "LISTING_TASKS":
        handle_task_list_type_selection(message)

    # Handle task editing steps

    # Handle task editing steps
    elif current_state == "EDITING_TASK_STEP_1":
        handle_edit_task_title(message)
    elif current_state == "EDITING_TASK_STEP_2":
        handle_edit_task_description(message)
    elif current_state == "EDITING_TASK_STEP_3":
        handle_edit_task_due_date(message)
    elif current_state == "EDITING_TASK_STEP_4":
        handle_edit_task_priority(message)
    elif current_state == "EDITING_TASK_STEP_5":
        handle_edit_task_reminder_time(message)
    elif current_state == "EDITING_TASK_STEP_6":
        handle_edit_task_category(message)
    elif current_state == "EDITING_TASK_STEP_6_SELECT":
        handle_edit_task_category_selection(message)  # New step to handle category selection in editing flow
    elif current_state == "EDITING_TASK_STEP_7":
        handle_edit_task_status(message)
    elif current_state == "CONFIRM_TASK_UPDATE":
        handle_task_update_confirmation_response(message)

    # Log an error if the state is unrecognized
    else:
        print(f"ERROR: Unrecognized state '{current_state}' for user {user_id}")
        bot.send_message(user_id, "❌ An error occurred. Please try again.")


def delete_task(user_id, task_id):
        try:
            task_ref = db.collection(u'tasks').document(task_id)
            task_ref.delete()
            bot.send_message(user_id, f"Task '{task_id}' deleted successfully!")
            print(f"DEBUG: Task {task_id} deleted for user {user_id}")  # Debugging
        except Exception as e:
            print(f"Error deleting task {task_id} for user {user_id}: {e}")

def handle_edit_task_step(message, step):
    """
    Handle the multi-step task editing process, ensuring it closely aligns with the task creation process.
    """
    user_id = message.chat.id
    debug_log(user_id, f"Handling step {step} of task editing")

    # Ensure the user is authenticated and a task is selected for editing
    if user_id not in user_states or 'user_uid' not in user_states[user_id] or 'task_id' not in user_states[user_id]:
        bot.send_message(user_id, "⚠️ Please select a task to edit or log in again using /start.")
        user_states[user_id] = {'status': 'AWAITING_EMAIL'}
        return
    
    user_uid = user_states[user_id].get('user_uid')
    debug_log(user_id, f"Step {step}: user_uid = {user_uid}")  # Debugging log

    try:


        task_id = user_states[user_id]['task_id']
        if step == 1:
            # Step 1: Ask for new task title
            bot.send_message(user_id, "Please enter the new title for the task.")
            user_states[user_id]['status'] = "EDITING_TASK_STEP_2"

        elif step == 2:
            # Step 2: Receive new title and ask for description
            title = message.text.strip()
            user_states[user_id]['new_task'] = {'title': title}
            bot.send_message(user_id, "Please enter the new description for the task.")
            user_states[user_id]['status'] = "EDITING_TASK_STEP_3"

        elif step == 3:
            # Step 3: Receive description and ask for due date
            description = message.text.strip()
            user_states[user_id]['new_task']['description'] = description
            bot.send_message(user_id, "Please enter the new due date (YYYY-MM-DD HH:MM).")
            user_states[user_id]['status'] = "EDITING_TASK_STEP_4"

        elif step == 4:
            # Step 4: Receive due date and ask for priority
            try:
                due_date = parse(message.text.strip())
                user_states[user_id]['new_task']['due_date'] = due_date
                bot.send_message(user_id, "Please enter the new priority (1- High, 2- Medium, 3- Low, 4- No Priority).")
                user_states[user_id]['status'] = "EDITING_TASK_STEP_5"
            except ValueError:
                bot.send_message(user_id, "❌ Invalid date format. Please enter the date in 'YYYY-MM-DD HH:MM' format.")
                return

        elif step == 5:
            # Step 5: Receive priority and ask for reminder time
            priority_input = message.text.strip()
            if priority_input in PRIORITY_LEVELS:
                user_states[user_id]['new_task']['priority_level'] = PRIORITY_LEVELS[priority_input]
                bot.send_message(user_id, "Please enter the new reminder time (e.g., '1 hour', '10 minutes').")
                user_states[user_id].update({'status': 'EDITING_TASK_STEP_6', 'user_uid': user_uid})
            else:
                bot.send_message(user_id, "❌ Invalid priority. Please enter a number between 1 and 4.")

        elif step == 6:
            # Step 6: Receive reminder time and ask for category
            reminder_time = message.text.strip()
            user_states[user_id]['new_task']['reminder_time'] = reminder_time

            # Fetch and display categories for selection
            categories = fetch_categories(user_id)
            if not categories:
                bot.send_message(user_id, "❌ No categories found. Please add a category first by typing /add_category.")
                user_states[user_id]['status'] = 'CHOOSING_ACTION'
                return

            category_options = "\n".join([f"{index + 1}. {name}" for index, name in enumerate(categories.values())])
            bot.send_message(user_id, f"Select a category by typing its number:\n{category_options}")
            user_states[user_id]['category_list'] = list(categories.items())
            user_states[user_id]['status'] = "EDITING_TASK_STEP_7"

        elif step == 7:
            # Step 7: Map category selection and ask for task status
            category_number = message.text.strip()
            category_index = int(category_number) - 1
            if 0 <= category_index < len(user_states[user_id]['category_list']):
                selected_category_id, _ = user_states[user_id]['category_list'][category_index]
                user_states[user_id]['new_task']['category_id'] = selected_category_id
                bot.send_message(user_id, "Please enter the new task status ('not started', 'in progress', 'completed').")
                user_states[user_id]['status'] = "EDITING_TASK_STEP_8"
            else:
                bot.send_message(user_id, "❌ Invalid category number.")

        elif step == 8:
            # Step 8: Confirm task status and finalize changes
            task_status = message.text.strip().lower()
            if task_status in ["not started", "in progress", "completed"]:
                user_states[user_id]['new_task']['task_status'] = task_status
                confirm_task_update(user_id)
            else:
                bot.send_message(user_id, "❌ Invalid task status. Please enter 'not started', 'in progress', or 'completed'.")

    except Exception as e:
        debug_log(user_id, f"Error occurred: {e}")
        bot.send_message(user_id, "❌ An error occurred while processing your request. Please try again.")

def confirm_task_update(user_id):
    """
    Confirm the updated task details with the user before applying changes to Firestore.
    """
    new_task = user_states[user_id]['new_task']
    confirmation_message = (
        f"Please confirm the updated task details:\n"
        f"📌 Title: {new_task['title']}\n"
        f"📝 Description: {new_task['description']}\n"
        f"📅 Due Date: {new_task['due_date'].strftime('%Y-%m-%d %H:%M')}\n"
        f"🔢 Priority: {new_task['priority_level']}\n"
        f"⏰ Reminder Time: {new_task['reminder_time']}\n"
        f"🗂️ Category: {new_task['category_id']}\n"
        f"📌 Status: {new_task['task_status']}\n\n"
        "Type 'yes' to confirm or 'no' to cancel."
    )
    bot.send_message(user_id, confirmation_message)
    user_states[user_id]['status'] = 'CONFIRM_TASK_UPDATE'
def handle_task_update_confirmation(user_id):
    """
    Confirm the updated task details with the user before applying changes to the database.
    """
    new_task = user_states[user_id]['new_task']
    
    # Fetch category name based on category_id
    categories = fetch_categories(user_id)  # Get all categories
    category_name = categories.get(new_task['category_id'], "Uncategorized")  # Default to "Uncategorized" if not found

    confirmation_message = (
        f"Please confirm the updated task details:\n"
        f"📌 Title: {new_task['title']}\n"
        f"📝 Description: {new_task['description']}\n"
        f"📅 Due Date: {new_task['due_date'].strftime('%Y-%m-%d %H:%M')}\n"
        f"🔢 Priority: {new_task['priority_level']}\n"
        f"⏰ Reminder Time: {new_task['reminder_time']}\n"
        f"🗂️ Category: {category_name}\n"  # Display category name instead of ID
        f"📌 Status: {new_task['task_status']}\n\n"
        "Type 'yes' to confirm or 'no' to cancel."
    )
    bot.send_message(user_id, confirmation_message)
    user_states[user_id]['status'] = 'CONFIRM_TASK_UPDATE'
    
@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'CONFIRM_TASK_UPDATE')
def handle_task_update_confirmation_response(message):
    user_id = message.chat.id
    if message.text.lower() == 'yes':
        # Apply the task update in Firestore
        task_id = user_states[user_id]['task_id']
        new_task = user_states[user_id]['new_task']
        update_task_in_db(user_id, task_id, new_task)

        # Reset the status
        bot.send_message(user_id, "✅ Task successfully updated!")
        send_welcome_message(user_id)
        user_states[user_id]['status'] = 'CHOOSING_ACTION'
    else:
        bot.send_message(user_id, "❌ Task update canceled.")
        send_welcome_message(user_id)
        user_states[user_id]['status'] = 'CHOOSING_ACTION'


def update_task_in_db(user_id, task_id, new_task):
    """
    Update the task in Firestore with new details and reschedule the notification if needed.
    """
    try:
        task_ref = db.collection(u'todos').document(task_id)
        
        # Prepare the update data
        update_data = {
            u'title': new_task['title'],
            u'description': new_task['description'],
            u'due_date': new_task['due_date'].strftime('%Y-%m-%d %H:%M'),
            u'priority_level': new_task['priority_level'],
            u'reminder_time': new_task['reminder_time'],
            u'category_id': new_task['category_id'],
            u'task_status': new_task['task_status']
        }
        
        # Perform the update
        task_ref.update(update_data)
        bot.send_message(user_id, "✅ Task successfully updated!")

        # Reschedule notifications with updated due date and reminder time
        cancel_notifications_for_task(task_id)
        schedule_notifications(task_id, user_id, new_task['description'], new_task['due_date'], new_task['reminder_time'])

    except Exception as e:
        print(f"Error updating task in Firestore for user {user_id}: {e}")
        bot.send_message(user_id, "❌ Failed to update the task. Please try again.")



def ask_task_list_type(user_id):
    user_states[user_id]['status'] = 'LISTING_TASKS'
    bot.send_message(
        user_id,
        "📅 Would you like to see tasks for:\n"
        "- 'today'\n"
        "- 'category' (Choose a category to filter by)\n"
        "- 'all' (All incomplete tasks)\n"
        "- 'completed' (All completed tasks)\n"
        "Please type 'today', 'category', 'all', or 'completed'."
    )

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'EDITING_TASK_STEP_1')
def handle_edit_task_title(message):
    user_id = message.chat.id
    print(f"DEBUG: Entered handle_edit_task_title for user {user_id}")

    try:
        print(f"DEBUG: Entered handle_edit_task_title for user {user_id}")
        
        # Process the title and move to next step
        new_title = message.text.strip()
        user_states[user_id]['new_task'] = user_states.get(user_id, {}).get('new_task', {})
        user_states[user_id]['new_task']['title'] = new_title
        
        bot.send_message(user_id, "Please enter the new description for the task.")
        user_states[user_id]['status'] = 'EDITING_TASK_STEP_2'
        
        print(f"DEBUG: Updated status to EDITING_TASK_STEP_2 for user {user_id}")
        
    except Exception as e:
        print(f"ERROR in handle_edit_task_title for user {user_id}: {e}")



@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'EDITING_TASK_STEP_2')
def handle_edit_task_description(message):
    user_id = message.chat.id
    new_description = message.text.strip()

    # Debugging log to confirm function entry
    print(f"DEBUG: Entering EDITING_TASK_STEP_2 for user {user_id}")
    
    # Store the new description and ask for the due date
    user_states[user_id]['new_task']['description'] = new_description
    bot.send_message(user_id, "Please enter the new due date (YYYY-MM-DD HH:MM).")
    user_states[user_id]['status'] = 'EDITING_TASK_STEP_3'

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status', '') == 'EDITING_TASK_STEP_3')
def handle_edit_task_due_date(message):
    user_id = message.chat.id
    try:
        new_due_date = parse(message.text.strip())
        user_states[user_id]['new_task']['due_date'] = new_due_date
        bot.send_message(user_id, "Please enter the new priority (1- High, 2- Medium, 3- Low, 4- No Priority).")
        user_states[user_id]['status'] = 'EDITING_TASK_STEP_4'
    except ValueError:
        bot.send_message(user_id, "❌ Invalid date format. Please enter the date in 'YYYY-MM-DD HH:MM' format.")


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status', '') == 'EDITING_TASK_STEP_4')
def handle_edit_task_priority(message):
    user_id = message.chat.id
    priority_input = message.text.strip()

    # Validate and store priority
    if priority_input in PRIORITY_LEVELS:
        user_states[user_id]['new_task']['priority_level'] = PRIORITY_LEVELS[priority_input]
        bot.send_message(user_id, "Please enter the new reminder time (e.g., '1 hour', '10 minutes').")
        user_states[user_id]['status'] = 'EDITING_TASK_STEP_5'
    else:
        bot.send_message(user_id, "❌ Invalid priority. Please enter a number between 1 and 4.")

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status', '') == 'EDITING_TASK_STEP_5')
def handle_edit_task_reminder_time(message):
    user_id = message.chat.id
    reminder_time = message.text.strip()

    # Store the reminder time and proceed to category selection
    user_states[user_id]['new_task']['reminder_time'] = reminder_time


    # Fetch categories using the Firebase `user_uid`
    categories = fetch_categories(user_id)

    # Display available categories to the user for selection
    if not categories:
        bot.send_message(user_id, "❌ No categories found. Please add a category first by typing /add_category.")
        user_states[user_id]['status'] = 'CHOOSING_ACTION'
        return

    # Format the list of categories with names
    category_options = "\n".join([f"{index + 1}. {name}" for index, name in enumerate(categories.values())])
    
    # Send the list of categories to the user
    bot.send_message(
        user_id,
        f"🔢 *Step 6: Select a Category*\nPlease choose a category by typing its number:\n{category_options}",
        parse_mode='Markdown'
    )

    # Store the categories list in `user_states` to map the selected number to the category ID
    user_states[user_id]['category_list'] = list(categories.items())  # Store (category_id, category_name) pairs
    user_states[user_id]['status'] = 'EDITING_TASK_STEP_6_SELECT'

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'EDITING_TASK_STEP_6')
def handle_edit_task_category(message):
    user_id = message.chat.id

    # Fetch categories using the Firebase user_uid from user_states
    categories = fetch_categories(user_id)
    
    # Display available categories to the user for selection
    if not categories:
        bot.send_message(user_id, "❌ No categories found. Please add a category first.")
        user_states[user_id]['status'] = 'CHOOSING_ACTION'
        return

    # Format the list of categories with names
    category_options = "\n".join([f"{index + 1}. {name}" for index, name in enumerate(categories.values())])
    
    # Send the list of categories to the user
    bot.send_message(
        user_id,
        f"🔢 *Step 6: Select a Category*\nPlease choose a category by typing its number:\n{category_options}",
        parse_mode='Markdown'
    )

    # Store the categories list in user_states to map the selected number to the category ID
    user_states[user_id]['category_list'] = list(categories.items())  # Store (category_id, category_name) pairs
    user_states[user_id]['status'] = 'EDITING_TASK_STEP_6_SELECT'

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status') == 'EDITING_TASK_STEP_6_SELECT')
def handle_edit_task_category_selection(message):
    user_id = message.chat.id
    category_number = message.text.strip()
    

    # Validate the input is a valid number within the range
    if not category_number.isdigit() or int(category_number) < 1 or int(category_number) > len(user_states[user_id]['category_list']):
        bot.send_message(user_id, "❌ Invalid category number. Please enter a valid number.")
        return

    # Map the selected number to the category ID
    category_index = int(category_number) - 1
    selected_category_id, selected_category_name = user_states[user_id]['category_list'][category_index]
    user_states[user_id]['new_task']['category_id'] = selected_category_id
    user_states[user_id]['status'] = 'EDITING_TASK_STEP_7'

    # Proceed to ask for task status
    bot.send_message(user_id, "Please enter the new task status ('not started', 'in progress', or 'completed').")


@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status', '') == 'EDITING_TASK_STEP_7')
def handle_edit_task_status(message):
    user_id = message.chat.id
    task_status = message.text.strip().lower()

    # Validate task status and confirm the update
    if task_status in ["not started", "in progress", "completed"]:
        user_states[user_id]['new_task']['task_status'] = task_status
        handle_task_update_confirmation(user_id)  # Confirm all changes
    else:
        bot.send_message(user_id, "❌ Invalid task status. Please enter 'not started', 'in progress', or 'completed'.")

def handle_task_update_confirmation(user_id):
    """
    Confirm the updated task details with the user before applying changes to the database.
    """
    new_task = user_states[user_id]['new_task']
    confirmation_message = (
        f"Please confirm the updated task details:\n"
        f"📌 Title: {new_task['title']}\n"
        f"📝 Description: {new_task['description']}\n"
        f"📅 Due Date: {new_task['due_date'].strftime('%Y-%m-%d %H:%M')}\n"
        f"🔢 Priority: {new_task['priority_level']}\n"
        f"⏰ Reminder Time: {new_task['reminder_time']}\n"
        f"🗂️ Category ID: {new_task['category_id']}\n"
        f"📌 Status: {new_task['task_status']}\n\n"
        "Type 'yes' to confirm or 'no' to cancel."
    )
    bot.send_message(user_id, confirmation_message)
    user_states[user_id]['status'] = 'CONFIRM_TASK_UPDATE'

@bot.message_handler(func=lambda message: user_states.get(message.chat.id, {}).get('status', '') == 'CONFIRM_TASK_UPDATE')
def handle_task_update_confirmation_response(message):
    user_id = message.chat.id
    if message.text.lower() == 'yes':
        # Apply the task update in Firestore
        new_task = user_states[user_id]['new_task']
        task_id = user_states[user_id]['task_id']
        update_task_in_db(user_id, task_id, new_task)
    else:
        bot.send_message(user_id, "❌ Task update canceled.")
    
    # Return to the main menu
    send_welcome_message(user_id)
    user_states[user_id]['status'] = 'CHOOSING_ACTION'


def update_task_in_db(user_id, task_id, new_task):
    """
    Update the task in Firestore with new details and reschedule the notification if needed.
    """
    try:
        task_ref = db.collection(u'todos').document(task_id)
        
        # Prepare the update data
        update_data = {
            u'title': new_task['title'],
            u'description': new_task['description'],
            u'due_date': new_task['due_date'].strftime('%Y-%m-%d %H:%M'),
            u'priority_level': new_task['priority_level'],
            u'reminder_time': new_task['reminder_time'],
            u'category_id': new_task['category_id'],
            u'task_status': new_task['task_status']
        }
        
        # Perform the update
        task_ref.update(update_data)
        bot.send_message(user_id, "✅ Task successfully updated!")

        # Reschedule notifications with updated due date and reminder time
        cancel_notifications_for_task(task_id)
        schedule_notifications(task_id, user_id, new_task['description'], new_task['due_date'], new_task['reminder_time'])
    except Exception as e:
        print(f"Error updating task in Firestore for user {user_id}: {e}")
        bot.send_message(user_id, "❌ Failed to update the task. Please try again.")

def cleanup_inactive_states():
    current_time = datetime.now()
    inactive_timeout = timedelta(hours=1)
    
    for chat_id in list(user_states.keys()):
        last_activity = user_states[chat_id].get('last_activity')
        if last_activity and (current_time - last_activity) > inactive_timeout:
            del user_states[chat_id]


# Start cleanup thread
cleanup_thread = threading.Thread(target=cleanup_inactive_states, daemon=True)
cleanup_thread.start()
notification_thread = threading.Thread(target=check_and_send_notifications)
notification_thread.start()
    # Start the bot and initialize the database
if __name__ == "__main__":
        bot.polling(none_stop=True)
