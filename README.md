# 🩸 Blood Link — Donate Blood, Save Lives

**Blood Link** is a Flutter-based blood donation and emergency blood request management application designed to connect blood donors with hospitals and NGOs. It aims to simplify emergency blood requests, improve donor coordination, and encourage regular blood donation through reminders and rewards.

## 📌 About the Project

During medical emergencies, finding suitable blood donors quickly can be challenging. Blood Link aims to provide a centralized digital platform where donors can manage their donation information and authorized organizations can coordinate emergency blood requests.

The application includes separate interfaces for donors and organizations, helping organize donor information, blood requests, and donation-related activities.

## 🎯 Objectives

- Simplify the process of raising emergency blood requests.
- Connect blood donors with hospitals and NGOs.
- Organize donor information for authorized organizations.
- Encourage regular blood donation through reminders.
- Improve emergency request coordination.
- Promote awareness of voluntary blood donation.

## ✨ Features

### 🧑 Donor Module

- Donor registration and login interface.
- Donor profile management.
- Blood group and personal information management.
- Donation history interface.
- Donation reminder interface.
- Emergency blood request alerts.
- Accept or decline donation requests.
- Rewards interface for donation-related activities.
- **Need Blood?** feature for submitting blood requests.

### 🏥 NGO & Hospital Module

- Organization login interface.
- Organization dashboard.
- Emergency blood request creation and management.
- Donor directory interface.
- Donor search and filtering by relevant details.
- Donor response coordination.
- Support for organizing donor information from Excel files.

### 🚨 Emergency Blood Requests

The application provides a form for submitting emergency blood requests, including:

- Patient name
- Required blood group
- Number of blood units
- Hospital name
- Location
- Contact information
- Urgency level
- Additional details

Actual request storage, donor matching, and real-time alerts depend on the corresponding backend implementation and configuration.

## 🛠️ Technology Stack

| Technology | Purpose |
|---|---|
| Flutter | Cross-platform application development |
| Dart | Application programming language |
| Firebase | Backend services and integration |
| Cloud Firestore | Database integration, where configured |
| Firebase Authentication | Authentication integration, where configured |
| Firebase Cloud Messaging | Push notifications, where configured |
| Firebase Cloud Functions | Server-side functions, where implemented |
| Git | Version control |
| GitHub | Source code hosting |

## 🏗️ Project Structure

```text
Blood-Link/
├── android/             # Android platform files
├── assets/              # App logo and image assets
├── functions/           # Firebase Cloud Functions
├── ios/                 # iOS platform files
├── lib/
│   ├── main.dart        # Main application code
│   ├── firebase_options.dart
│   └── emergency_request_details_screen.dart
├── linux/               # Linux platform files
├── macos/               # macOS platform files
├── test/                # Application tests
├── web/                 # Web platform files
├── windows/             # Windows platform files
├── firebase.json        # Firebase configuration
├── pubspec.yaml         # Flutter dependencies
└── README.md
```

## ⚙️ Installation and Setup

### Prerequisites

Install the following tools:

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Android Studio](https://developer.android.com/studio) or [Visual Studio Code](https://code.visualstudio.com/)
- [Git](https://git-scm.com/downloads)
- An Android device with USB debugging enabled or an Android emulator

### Step 1: Clone the Repository

```bash
git clone https://github.com/nazru7200/Blood-Link.git
```

### Step 2: Navigate to the Project

```bash
cd Blood-Link
```

### Step 3: Install Dependencies

```bash
flutter pub get
```

### Step 4: Check the Flutter Environment

```bash
flutter doctor
```

Resolve any required setup issues reported by Flutter.

### Step 5: Configure Firebase

If your current version uses Firebase services:

1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Create or select your Firebase project.
3. Register the relevant application platforms.
4. Configure the required Firebase services.
5. Verify the application configuration files.
6. Set up authentication, database rules, and Cloud Functions as required.

Never commit service-account private keys, passwords, or other secrets to GitHub. Configure appropriate access rules before storing real donor or patient information.

### Step 6: Run the Application

Connect an Android device or start an emulator, then run:

```bash
flutter run
```

## 🔐 Privacy and Security

Blood Link is intended to handle donor and patient information responsibly.

- Restrict sensitive donor information to authorized organizations.
- Verify organization accounts before granting access.
- Apply appropriate authentication and database security rules.
- Protect private credentials and configuration secrets.
- Avoid exposing patient contact information unnecessarily.
- Use authorized access when importing or exporting donor records.

Blood donation eligibility and medical decisions must be determined by qualified healthcare professionals.

## 🚀 Future Enhancements

- Real-time emergency blood request notifications.
- Automated donor matching by blood group and location.
- Firebase-backed donor and request management.
- Improved donor availability tracking.
- Donation certificate verification.
- Reward tracking and donor engagement.
- Excel-based donor data import and export.
- Enhanced organization dashboards and analytics.
- Testing, deployment, and potential Play Store publication.

## 👨‍💻 Developer

**A. Nazru Deen**  
Flutter Developer | AI & Machine Learning Engineering Student

- **GitHub:** [nazru7200](https://github.com/nazru7200)
- **LinkedIn:** [A. Nazru Deen](https://www.linkedin.com/in/nazrudeen-72008-9255ph/)

## License

This project is licensed under the MIT License.

---

## ❤️ Our Mission

**Donate Blood. Save Lives. Build a Connected Community.**

Blood Link aims to make blood donation coordination more accessible and organized, helping donors and authorized organizations work together during emergencies.
