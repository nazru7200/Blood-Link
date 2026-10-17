import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

final AppLinks appLinks = AppLinks();

String? pendingEmergencyRequestId;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Request notification permission
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const BloodLinkApp());
}
// ============================================================
// BLOOD LINK APP
// ============================================================

class BloodLinkApp extends StatefulWidget {
  const BloodLinkApp({super.key});

  @override
  State<BloodLinkApp> createState() => _BloodLinkAppState();
}

class _BloodLinkAppState extends State<BloodLinkApp> {
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();

    _initializeDeepLinks();
  }

  Future<void> _initializeDeepLinks() async {
    try {
      // ------------------------------------------------------------
      // APP LINK WHEN APP IS ALREADY OPEN / RUNNING
      // ------------------------------------------------------------

      _linkSubscription = appLinks.uriLinkStream.listen(
        (Uri uri) {
          _handleEmergencyLink(uri);
        },
        onError: (error) {
          debugPrint('App Link Error: $error');
        },
      );

      // ------------------------------------------------------------
      // APP LINK WHEN APP IS CLOSED AND OPENED FROM THE LINK
      // ------------------------------------------------------------

      final Uri? initialUri = await appLinks.getInitialLink();

      if (initialUri != null) {
        _handleEmergencyLink(initialUri);
      }
    } catch (e) {
      debugPrint('Deep link initialization error: $e');
    }
  }

  void _handleEmergencyLink(Uri uri) {
    debugPrint('Blood Link received URI: $uri');

    if (uri.scheme != 'https') {
      return;
    }

    if (uri.host !=
        'floral-salad-b086.nazrudeen7200.workers.dev') {
      return;
    }

    if (!uri.path.startsWith('/emergency/')) {
      return;
    }

    final String requestId =
        uri.path.substring('/emergency/'.length).trim();

    if (requestId.isEmpty) {
      return;
    }

    debugPrint(
      'Blood Link Emergency Request ID: $requestId',
    );

    final User? user =
        FirebaseAuth.instance.currentUser;

    // ------------------------------------------------------------
    // USER IS NOT LOGGED IN
    // ------------------------------------------------------------

    if (user == null) {
      pendingEmergencyRequestId = requestId;

      debugPrint(
        'Emergency link saved. Waiting for donor login.',
      );

      return;
    }

    // ------------------------------------------------------------
    // USER IS ALREADY LOGGED IN
    // ------------------------------------------------------------

    _openEmergencyRequest(requestId);
  }

  void _openEmergencyRequest(String requestId) {
    final NavigatorState? navigator =
        navigatorKey.currentState;

    if (navigator == null) {
      pendingEmergencyRequestId = requestId;
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (context) =>
            EmergencyRequestLinkScreen(
          requestId: requestId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Blood Link',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
// ============================================================
// LOGIN SCREEN
// ============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------

  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  // ------------------------------------------------------------
  // LOGIN SETTINGS
  // ------------------------------------------------------------

  bool hidePassword = true;
  String selectedRole = 'Donor';
  bool isLoginLoading = false;

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------
  // SAVE FCM TOKEN
  // ------------------------------------------------------------

  Future<void> _saveFcmToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        debugPrint('FCM: No logged-in user.');
        return;
      }

      debugPrint('FCM: Getting device token...');

      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        debugPrint('FCM: Token is NULL.');
        return;
      }

      debugPrint('FCM: Token received.');

      await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      debugPrint('FCM: Token saved to Firestore successfully.');
    } catch (e) {
      debugPrint('FCM ERROR: $e');
    }
  }

  // ------------------------------------------------------------
  // DONOR LOGIN
  // ------------------------------------------------------------

  Future<void> _donorLogin() async {
    final String phone = phoneController.text.trim();
    final String password = passwordController.text;

    // ----------------------------------------------------------
    // VALIDATION
    // ----------------------------------------------------------

    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your phone number and password.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // CLEAN PHONE NUMBER
    // ----------------------------------------------------------

    final String cleanedPhone = phone.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (cleanedPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid phone number.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // START LOADING
    // ----------------------------------------------------------

    setState(() {
      isLoginLoading = true;
    });

    try {
      // --------------------------------------------------------
      // CREATE SAME INTERNAL IDENTIFIER USED DURING REGISTRATION
      // --------------------------------------------------------

      final String loginIdentifier =
          '$cleanedPhone@bloodlink.local';

      // --------------------------------------------------------
      // FIREBASE AUTHENTICATION
      // --------------------------------------------------------

      final UserCredential userCredential =
          await FirebaseAuth.instance
              .signInWithEmailAndPassword(
        email: loginIdentifier,
        password: password,
      );

      final User? user = userCredential.user;

      if (user == null) {
        throw Exception(
          'Unable to find Firebase user.',
        );
      }

      // --------------------------------------------------------
      // CHECK DONOR PROFILE IN FIRESTORE
      // --------------------------------------------------------

      final DocumentSnapshot<Map<String, dynamic>>
          donorDocument =
          await FirebaseFirestore.instance
              .collection('donors')
              .doc(user.uid)
              .get();

      if (!donorDocument.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          isLoginLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Donor profile not found. Please contact Blood Link support.',
            ),
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // SAVE FCM TOKEN
      // --------------------------------------------------------
      //
      // This connects this donor's phone with Firebase Cloud
      // Messaging so emergency notifications can be sent later.
      //

      await _saveFcmToken();

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const DonorHomeScreen(),
        ),
      );
    }

    // ----------------------------------------------------------
    // FIREBASE AUTH ERROR
    // ----------------------------------------------------------

    on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message =
              'Invalid phone number or password.';
          break;

        case 'user-not-found':
          message =
              'No donor account found with this phone number.';
          break;

        case 'wrong-password':
          message =
              'Incorrect password.';
          break;

        case 'invalid-email':
          message =
              'Invalid phone number.';
          break;

        case 'user-disabled':
          message =
              'This donor account has been disabled.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. Please try again later.';
          break;

        case 'network-request-failed':
          message =
              'Network error. Please check your internet connection.';
          break;

        default:
          message =
              e.message ??
              'Unable to login.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }

    // ----------------------------------------------------------
    // OTHER ERROR
    // ----------------------------------------------------------

    catch (e) {
      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      debugPrint(
        'Donor login error: $e',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong. Please try again.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // NGO / HOSPITAL LOGIN
  // ------------------------------------------------------------

  Future<void> _organizationLogin() async {
    final String organizationId =
        phoneController.text.trim().toLowerCase();

    final String password = passwordController.text;

    // ----------------------------------------------------------
    // VALIDATION
    // ----------------------------------------------------------

    if (organizationId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your organization ID and password.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // START LOADING
    // ----------------------------------------------------------

    setState(() {
      isLoginLoading = true;
    });

    try {
      // --------------------------------------------------------
      // CREATE INTERNAL FIREBASE LOGIN IDENTIFIER
      // --------------------------------------------------------

      final String loginIdentifier =
          '$organizationId@bloodlink.local';

      // --------------------------------------------------------
      // FIREBASE AUTHENTICATION
      // --------------------------------------------------------

      final UserCredential userCredential =
          await FirebaseAuth.instance
              .signInWithEmailAndPassword(
        email: loginIdentifier,
        password: password,
      );

      final User? user = userCredential.user;

      if (user == null) {
        throw Exception(
          'Unable to find organization account.',
        );
      }

      // --------------------------------------------------------
      // GET ORGANIZATION PROFILE
      // --------------------------------------------------------

      final DocumentSnapshot<Map<String, dynamic>>
          organizationDocument =
          await FirebaseFirestore.instance
              .collection('organizations')
              .doc(user.uid)
              .get();

      // --------------------------------------------------------
      // ORGANIZATION PROFILE NOT FOUND
      // --------------------------------------------------------

      if (!organizationDocument.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          isLoginLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Organization profile not found. Please contact the Blood Link administrator.',
            ),
          ),
        );

        return;
      }

      final Map<String, dynamic> organizationData =
          organizationDocument.data()!;

      // --------------------------------------------------------
      // CHECK ROLE
      // --------------------------------------------------------

      final String role =
          organizationData['role']?.toString() ?? '';

      if (role != 'organization') {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          isLoginLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This account is not authorized as an organization.',
            ),
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // CHECK VERIFICATION
      // --------------------------------------------------------

      final bool isVerified =
          organizationData['isVerified'] == true;

      if (!isVerified) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          isLoginLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This organization account has not been verified.',
            ),
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const OrganizationHomeScreen(),
        ),
      );
    }

    // ----------------------------------------------------------
    // FIREBASE AUTH ERROR
    // ----------------------------------------------------------

    on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message =
              'Invalid organization ID or password.';
          break;

        case 'user-not-found':
          message =
              'Organization account not found.';
          break;

        case 'wrong-password':
          message =
              'Incorrect organization password.';
          break;

        case 'invalid-email':
          message =
              'Invalid organization ID.';
          break;

        case 'user-disabled':
          message =
              'This organization account has been disabled.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. Please try again later.';
          break;

        case 'network-request-failed':
          message =
              'Network error. Please check your internet connection.';
          break;

        default:
          message =
              e.message ??
              'Unable to login as organization.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }

    // ----------------------------------------------------------
    // OTHER ERROR
    // ----------------------------------------------------------

    catch (e) {
      if (!mounted) return;

      setState(() {
        isLoginLoading = false;
      });

      debugPrint(
        'Organization login error: $e',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong. Please try again.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isDonor = selectedRole == 'Donor';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 45),

              // ------------------------------------------------
              // BLOOD LINK LOGO
              // ------------------------------------------------

              Image.asset(
                'assets/logo.png',
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 8),

              // ------------------------------------------------
              // TAGLINE
              // ------------------------------------------------

              const Text(
                'Connecting blood donors with people in need',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 35),

              // ------------------------------------------------
              // LOGIN TYPE
              // ------------------------------------------------

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Login Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.account_circle,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Donor',
                    child: Text(
                      'Donor',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'NGO / Hospital',
                    child: Text(
                      'NGO / Hospital',
                    ),
                  ),
                ],
                onChanged: isLoginLoading
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          selectedRole = value;

                          phoneController.clear();
                          passwordController.clear();
                        });
                      },
              ),

              const SizedBox(height: 18),

              // ------------------------------------------------
              // PHONE / ORGANIZATION ID
              // ------------------------------------------------

              TextField(
                controller: phoneController,
                enabled: !isLoginLoading,
                keyboardType: isDonor
                    ? TextInputType.phone
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: isDonor
                      ? 'Phone Number'
                      : 'Organization ID',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    isDonor
                        ? Icons.phone
                        : Icons.local_hospital,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ------------------------------------------------
              // PASSWORD
              // ------------------------------------------------

              TextField(
                controller: passwordController,
                enabled: !isLoginLoading,
                obscureText: hidePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.lock,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      hidePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: isLoginLoading
                        ? null
                        : () {
                            setState(() {
                              hidePassword =
                                  !hidePassword;
                            });
                          },
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // LOGIN BUTTON
              // ------------------------------------------------

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                  onPressed: isLoginLoading
                      ? null
                      : () async {
                          if (selectedRole == 'Donor') {
                            await _donorLogin();
                          } else {
                            await _organizationLogin();
                          }
                        },
                  child: isLoginLoading
                      ? const SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 18),

              // ------------------------------------------------
              // DONOR REGISTRATION
              // ------------------------------------------------

              if (isDonor)
                TextButton(
                  onPressed: isLoginLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const RegisterScreen(),
                            ),
                          );
                        },
                  child: const Text(
                    'Create Donor Account',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                    ),
                  ),
                ),

              // ------------------------------------------------
              // ORGANIZATION MESSAGE
              // ------------------------------------------------

              if (!isDonor)
                const Padding(
                  padding: EdgeInsets.only(
                    top: 5,
                  ),
                  child: Text(
                    'NGO / Hospital accounts are provided by the Blood Link administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // ABOUT BLOOD LINK
              // ------------------------------------------------

              TextButton.icon(
                onPressed: isLoginLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const AboutBloodLinkScreen(),
                          ),
                        );
                      },
                icon: const Icon(
                  Icons.info_outline,
                  color: Colors.red,
                ),
                label: const Text(
                  'About Blood Link',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================
// DONOR REGISTRATION SCREEN
// ============================================================

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ------------------------------------------------------------
  // TEXT CONTROLLERS
  // ------------------------------------------------------------

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final locationController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // ------------------------------------------------------------
  // FORM VALUES
  // ------------------------------------------------------------

  String bloodGroup = 'A+';

  bool donatedBefore = false;

  DateTime? lastDonationDate;

  int previousDonationCount = 0;

  bool isLoading = false;

  // ------------------------------------------------------------
  // DISPOSE CONTROLLERS
  // ------------------------------------------------------------

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    locationController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------
  // CREATE INTERNAL LOGIN IDENTIFIER
  // ------------------------------------------------------------
  // Firebase Email/Password authentication requires an email
  // identifier.
  //
  // The user will NOT see or enter this identifier.
  //
  // Example:
  // 9876543210
  // becomes
  // 9876543210@bloodlink.local
  //
  // The visible Blood Link login will continue to use:
  // Phone Number + Password
  // ------------------------------------------------------------

  String _createLoginIdentifier(String phone) {
    final cleanedPhone = phone.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return '$cleanedPhone@bloodlink.local';
  }

  // ------------------------------------------------------------
  // SHOW MESSAGE
  // ------------------------------------------------------------

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ------------------------------------------------------------
  // REGISTER DONOR
  // ------------------------------------------------------------

  Future<void> _registerDonor() async {
    // ----------------------------------------------------------
    // GET FORM VALUES
    // ----------------------------------------------------------

    final String name = nameController.text.trim();

    final String phone = phoneController.text.trim();

    final String location = locationController.text.trim();

    final String password = passwordController.text;

    final String confirmPassword =
        confirmPasswordController.text;

    // ----------------------------------------------------------
    // REQUIRED FIELD VALIDATION
    // ----------------------------------------------------------

    if (name.isEmpty ||
        phone.isEmpty ||
        location.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage(
        'Please fill all the required fields.',
      );

      return;
    }

    // ----------------------------------------------------------
    // PHONE VALIDATION
    // ----------------------------------------------------------

    final String cleanedPhone = phone.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (cleanedPhone.length < 10) {
      _showMessage(
        'Please enter a valid phone number.',
      );

      return;
    }

    // ----------------------------------------------------------
    // PASSWORD VALIDATION
    // ----------------------------------------------------------

    if (password.length < 6) {
      _showMessage(
        'Password must contain at least 6 characters.',
      );

      return;
    }

    // ----------------------------------------------------------
    // CONFIRM PASSWORD
    // ----------------------------------------------------------

    if (password != confirmPassword) {
      _showMessage(
        'Passwords do not match.',
      );

      return;
    }

    // ----------------------------------------------------------
    // PREVIOUS DONATION VALIDATION
    // ----------------------------------------------------------

    if (donatedBefore) {
      if (lastDonationDate == null) {
        _showMessage(
          'Please select your last donation date.',
        );

        return;
      }

      if (previousDonationCount == 0) {
        _showMessage(
          'Please select your approximate previous donation count.',
        );

        return;
      }
    }

    // ----------------------------------------------------------
    // START LOADING
    // ----------------------------------------------------------

    setState(() {
      isLoading = true;
    });

    User? createdUser;

    try {
      // --------------------------------------------------------
      // CREATE INTERNAL LOGIN IDENTIFIER
      // --------------------------------------------------------

      final String loginIdentifier =
          _createLoginIdentifier(cleanedPhone);

      // --------------------------------------------------------
      // CREATE FIREBASE AUTH ACCOUNT
      // --------------------------------------------------------

      final UserCredential userCredential =
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
        email: loginIdentifier,
        password: password,
      );

      createdUser = userCredential.user;

      if (createdUser == null) {
        throw Exception(
          'Firebase user could not be created.',
        );
      }

      // --------------------------------------------------------
      // PREVIOUS DONATION DATA
      // --------------------------------------------------------

      Timestamp? lastDonationTimestamp;

      if (donatedBefore && lastDonationDate != null) {
        lastDonationTimestamp =
            Timestamp.fromDate(lastDonationDate!);
      }

      final int savedDonationCount =
          donatedBefore
              ? previousDonationCount
              : 0;

      // --------------------------------------------------------
      // FIRESTORE DONOR DOCUMENT
      // --------------------------------------------------------

      await FirebaseFirestore.instance
          .collection('donors')
          .doc(createdUser.uid)
          .set({
        // Basic donor information
        'name': name,
        'phone': cleanedPhone,
        'bloodGroup': bloodGroup,
        'location': location,

        // Account role
        'role': 'donor',

        // Previous donation information
        'donatedBefore': donatedBefore,
        'lastDonationDate': lastDonationTimestamp,
        'previousDonationCount': savedDonationCount,

        // Previous history is NOT automatically considered
        // medically verified.
        'historyVerified': false,
        'historyVerificationStatus':
            'self-reported-unverified',

        // Current donor availability
        'availability': true,

        // Total donation count currently known by Blood Link.
        'donationCount': savedDonationCount,

        // Account creation time
        'createdAt': FieldValue.serverTimestamp(),
      });

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Account Created',
            ),

            content: const Text(
              'Your Blood Link donor account has been '
              'created successfully. You can now login '
              'using your phone number and password.',
            ),

            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      // --------------------------------------------------------
      // RETURN TO LOGIN SCREEN
      // --------------------------------------------------------

      if (!mounted) return;

      Navigator.pop(context);
    }

    // ----------------------------------------------------------
    // FIREBASE AUTHENTICATION ERROR
    // ----------------------------------------------------------

    on FirebaseAuthException catch (e) {
      // If authentication succeeded but Firestore failed later,
      // createdUser will be handled by the general catch block.
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message =
              'An account already exists with this phone number.';
          break;

        case 'weak-password':
          message =
              'Password is too weak. Please use at least 6 characters.';
          break;

        case 'invalid-email':
          message =
              'Unable to create the account with this phone number.';
          break;

        case 'operation-not-allowed':
          message =
              'Email/Password authentication is not enabled in Firebase.';
          break;

        case 'network-request-failed':
          message =
              'Network error. Please check your internet connection.';
          break;

        default:
          message =
              e.message ??
              'Unable to create the donor account.';
      }

      _showMessage(message);
    }

    // ----------------------------------------------------------
    // FIRESTORE / OTHER ERROR
    // ----------------------------------------------------------

    catch (e) {
      // --------------------------------------------------------
      // REMOVE AUTH ACCOUNT IF FIRESTORE SAVE FAILED
      // --------------------------------------------------------
      // This prevents an authentication account from being left
      // behind without its donor profile.
      // --------------------------------------------------------

      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (deleteError) {
          debugPrint(
            'Could not remove incomplete auth account: '
            '$deleteError',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      debugPrint(
        'Donor registration error: $e',
      );

      _showMessage(
        'Unable to complete registration. Please try again.',
      );
    }
  }

  // ------------------------------------------------------------
  // BUILD UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Donor Registration',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            // --------------------------------------------------
            // HEADER
            // --------------------------------------------------

            const Icon(
              Icons.volunteer_activism,
              size: 75,
              color: Colors.red,
            ),

            const SizedBox(height: 10),

            const Text(
              'Become a Blood Donor',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Create your Blood Link donor account',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 25),

            // --------------------------------------------------
            // FULL NAME
            // --------------------------------------------------

            TextField(
              controller: nameController,
              textCapitalization:
                  TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.person,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // PHONE NUMBER
            // --------------------------------------------------

            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.phone,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // BLOOD GROUP
            // --------------------------------------------------

            DropdownButtonFormField<String>(
              initialValue: bloodGroup,

              decoration: const InputDecoration(
                labelText: 'Blood Group',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.bloodtype,
                ),
              ),

              items: const [
                DropdownMenuItem(
                  value: 'A+',
                  child: Text('A+'),
                ),
                DropdownMenuItem(
                  value: 'A-',
                  child: Text('A-'),
                ),
                DropdownMenuItem(
                  value: 'B+',
                  child: Text('B+'),
                ),
                DropdownMenuItem(
                  value: 'B-',
                  child: Text('B-'),
                ),
                DropdownMenuItem(
                  value: 'AB+',
                  child: Text('AB+'),
                ),
                DropdownMenuItem(
                  value: 'AB-',
                  child: Text('AB-'),
                ),
                DropdownMenuItem(
                  value: 'O+',
                  child: Text('O+'),
                ),
                DropdownMenuItem(
                  value: 'O-',
                  child: Text('O-'),
                ),
              ],

              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  bloodGroup = value;
                });
              },
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // LOCATION
            // --------------------------------------------------

            TextField(
              controller: locationController,
              textCapitalization:
                  TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.location_on,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // PREVIOUS DONATION QUESTION
            // --------------------------------------------------

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Have you donated blood before?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // YES / NO BUTTONS
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        donatedBefore = true;
                      });
                    },

                    icon: Icon(
                      donatedBefore
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Colors.red,
                    ),

                    label: const Text(
                      'Yes',
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        donatedBefore = false;
                        lastDonationDate = null;
                        previousDonationCount = 0;
                      });
                    },

                    icon: Icon(
                      !donatedBefore
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Colors.red,
                    ),

                    label: const Text(
                      'No',
                    ),
                  ),
                ),
              ],
            ),

            // --------------------------------------------------
            // PREVIOUS DONATION DETAILS
            // --------------------------------------------------

            if (donatedBefore) ...[
              const SizedBox(height: 15),

              // ----------------------------------------------
              // LAST DONATION DATE
              // ----------------------------------------------

              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.calendar_month,
                    color: Colors.red,
                  ),

                  title: const Text(
                    'Last Donation Date',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  subtitle: Text(
                    lastDonationDate == null
                        ? 'Select your last donation date'
                        : '${lastDonationDate!.day}/'
                            '${lastDonationDate!.month}/'
                            '${lastDonationDate!.year}',
                  ),

                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                  ),

                  onTap: () async {
                    final DateTime? pickedDate =
                        await showDatePicker(
                      context: context,

                      initialDate:
                          lastDonationDate ??
                          DateTime.now(),

                      firstDate:
                          DateTime(1950),

                      lastDate:
                          DateTime.now(),
                    );

                    if (pickedDate != null) {
                      setState(() {
                        lastDonationDate =
                            pickedDate;
                      });
                    }
                  },
                ),
              ),

              const SizedBox(height: 15),

              // ----------------------------------------------
              // PREVIOUS DONATION COUNT
              // ----------------------------------------------

              DropdownButtonFormField<int>(
                initialValue:
                    previousDonationCount == 0
                        ? null
                        : previousDonationCount,

                decoration: const InputDecoration(
                  labelText:
                      'Approximate Previous Donations',
                  border:
                      OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.volunteer_activism,
                  ),
                ),

                items: const [
                  DropdownMenuItem(
                    value: 1,
                    child: Text(
                      '1 donation',
                    ),
                  ),

                  DropdownMenuItem(
                    value: 2,
                    child: Text(
                      '2 donations',
                    ),
                  ),

                  DropdownMenuItem(
                    value: 3,
                    child: Text(
                      '3 donations',
                    ),
                  ),

                  DropdownMenuItem(
                    value: 5,
                    child: Text(
                      '4–5 donations',
                    ),
                  ),

                  DropdownMenuItem(
                    value: 10,
                    child: Text(
                      '6–10 donations',
                    ),
                  ),

                  DropdownMenuItem(
                    value: 11,
                    child: Text(
                      'More than 10 donations',
                    ),
                  ),
                ],

                onChanged: (value) {
                  setState(() {
                    previousDonationCount =
                        value ?? 0;
                  });
                },
              ),

              const SizedBox(height: 12),

              // ----------------------------------------------
              // VERIFICATION INFORMATION
              // ----------------------------------------------

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius:
                      BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                ),

                child: const Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                    ),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'Previous donation information will '
                        'be saved as self-reported and '
                        'unverified. An authorized blood bank '
                        'or Blood Link organization can verify '
                        'the information later.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 15),

            // --------------------------------------------------
            // PASSWORD
            // --------------------------------------------------

            TextField(
              controller: passwordController,
              obscureText: true,

              decoration: const InputDecoration(
                labelText: 'Create Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.lock,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // CONFIRM PASSWORD
            // --------------------------------------------------

            TextField(
              controller:
                  confirmPasswordController,
              obscureText: true,

              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.lock_outline,
                ),
              ),
            ),

            const SizedBox(height: 25),

            // --------------------------------------------------
            // CREATE ACCOUNT BUTTON
            // --------------------------------------------------

            SizedBox(
              width: double.infinity,
              height: 55,

              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      Colors.grey,
                ),

                onPressed:
                    isLoading
                        ? null
                        : _registerDonor,

                child: isLoading
                    ? const SizedBox(
                        width: 25,
                        height: 25,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'CREATE DONOR ACCOUNT',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // LOGIN INFORMATION
            // --------------------------------------------------

            const Text(
              'No OTP required. You will use your phone '
              'number and password to login.',
              textAlign: TextAlign.center,

              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 10),

            // --------------------------------------------------
            // PRIVACY / VERIFICATION INFORMATION
            // --------------------------------------------------

            const Text(
              'Your donor information is securely stored '
              'and is not publicly visible. Previous donation '
              'history remains unverified until confirmed by '
              'an authorized organization.',
              textAlign: TextAlign.center,

              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DONOR PROFILE SCREEN
// ============================================================

// ============================================================
// DONOR PROFILE SCREEN
// ============================================================

class DonorProfileScreen extends StatefulWidget {
  const DonorProfileScreen({super.key});

  @override
  State<DonorProfileScreen> createState() =>
      _DonorProfileScreenState();
}

class _DonorProfileScreenState
    extends State<DonorProfileScreen> {
  bool isLoading = true;
  bool isUpdatingAvailability = false;

  Map<String, dynamic>? donorData;

  // ------------------------------------------------------------
  // LOAD DONOR PROFILE
  // ------------------------------------------------------------

  Future<void> _loadDonorProfile() async {
    try {
      final User? user =
          FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
        });

        return;
      }

      final DocumentSnapshot<Map<String, dynamic>>
          document =
          await FirebaseFirestore.instance
              .collection('donors')
              .doc(user.uid)
              .get();

      if (!mounted) return;

      if (document.exists) {
        setState(() {
          donorData = document.data();
          isLoading = false;
        });
      } else {
        setState(() {
          donorData = null;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Error loading donor profile: $e',
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to load your profile.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // UPDATE AVAILABILITY
  // ------------------------------------------------------------

  Future<void> _updateAvailability(
    bool value,
  ) async {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      isUpdatingAvailability = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .update({
        'availability': value,
      });

      if (!mounted) return;

      setState(() {
        donorData?['availability'] = value;
        isUpdatingAvailability = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'You are now available for blood donation.'
                : 'You are now unavailable for blood donation.',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Availability update error: $e',
      );

      if (!mounted) return;

      setState(() {
        isUpdatingAvailability = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to update availability.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // FORMAT DATE
  // ------------------------------------------------------------

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'Not available';
    }

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }

    if (date == null) {
      return 'Not available';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ------------------------------------------------------------
  // LOGOUT
  // ------------------------------------------------------------

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const LoginScreen(),
      ),
      (route) => false,
    );
  }

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadDonorProfile();
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // ----------------------------------------------------------
    // LOADING
    // ----------------------------------------------------------

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'My Profile',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Colors.red,
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // NO PROFILE
    // ----------------------------------------------------------

    if (donorData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'My Profile',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_off,
                  size: 70,
                  color: Colors.grey,
                ),

                const SizedBox(height: 15),

                const Text(
                  'Donor profile not found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Please contact Blood Link support if '
                  'you believe this is an error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 25),

                ElevatedButton(
                  onPressed: _logout,
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'LOGOUT',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // PROFILE DATA
    // ----------------------------------------------------------

    final String name =
        donorData!['name']?.toString() ??
            'Not available';

    final String phone =
        donorData!['phone']?.toString() ??
            'Not available';

    final String bloodGroup =
        donorData!['bloodGroup']?.toString() ??
            'Not available';

    final String location =
        donorData!['location']?.toString() ??
            'Not available';

    final String lastDonation =
        _formatDate(
      donorData!['lastDonationDate'],
    );

    final int donationCount =
        donorData!['donationCount'] is int
            ? donorData!['donationCount'] as int
            : 0;

    final int previousDonationCount =
        donorData!['previousDonationCount'] is int
            ? donorData!['previousDonationCount']
                as int
            : 0;

    final bool availability =
        donorData!['availability'] == true;

    final bool historyVerified =
        donorData!['historyVerified'] == true;

    final String historyStatus =
        historyVerified
            ? 'Verified'
            : 'Self-reported / Unverified';

    // ----------------------------------------------------------
    // PROFILE UI
    // ----------------------------------------------------------

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadDonorProfile,
            icon: const Icon(
              Icons.refresh,
            ),
            tooltip: 'Refresh',
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _loadDonorProfile,

        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [
              // ------------------------------------------------
              // PROFILE HEADER
              // ------------------------------------------------

              Center(
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 48,
                      backgroundColor:
                          Colors.red,
                      child: Icon(
                        Icons.person,
                        size: 55,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Blood Group: $bloodGroup',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.red,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // PERSONAL INFORMATION
              // ------------------------------------------------

              const Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.person,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Full Name',
                      ),
                      subtitle: Text(
                        name,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.phone,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Phone Number',
                      ),
                      subtitle: Text(
                        phone,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Location',
                      ),
                      subtitle: Text(
                        location,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // BLOOD DONATION INFORMATION
              // ------------------------------------------------

              const Text(
                'Blood Donation Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.bloodtype,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Blood Group',
                      ),
                      subtitle: Text(
                        bloodGroup,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.calendar_today,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Last Donation',
                      ),
                      subtitle: Text(
                        lastDonation,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.volunteer_activism,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Donation Count',
                      ),
                      subtitle: Text(
                        '$donationCount verified donations',
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.history,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Previous Donations',
                      ),
                      subtitle: Text(
                        '$previousDonationCount '
                        'self-reported donations',
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: Icon(
                        historyVerified
                            ? Icons.verified
                            : Icons.info_outline,
                        color: historyVerified
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text(
                        'History Status',
                      ),
                      subtitle: Text(
                        historyStatus,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // AVAILABILITY
              // ------------------------------------------------

              const Text(
                'Donation Availability',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Card(
                child: SwitchListTile(
                  value: availability,

                  onChanged:
                      isUpdatingAvailability
                          ? null
                          : _updateAvailability,

                  activeThumbColor:
                      Colors.red,

                  title: const Text(
                    'Available for Blood Donation',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  subtitle: Text(
                    availability
                        ? 'You may receive suitable emergency alerts.'
                        : 'You will not be considered available for alerts.',
                  ),

                  secondary: Icon(
                    availability
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: availability
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // PRIVACY INFORMATION
              // ------------------------------------------------

              Card(
                color: Colors.red.shade50,

                child: const Padding(
                  padding: EdgeInsets.all(16),

                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      Icon(
                        Icons.lock,
                        color: Colors.red,
                      ),

                      SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          'Your donor information is protected. '
                          'Only authorized Blood Link organizations '
                          'can access donor information required for '
                          'legitimate blood donation coordination.',
                          style: TextStyle(
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // EDIT PROFILE
              // ------------------------------------------------

              SizedBox(
                width: double.infinity,
                height: 50,

                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const EditDonorProfileScreen(),
                      ),
                    );

                    if (!mounted) return;

                    await _loadDonorProfile();
                  },

                  icon: const Icon(
                    Icons.edit,
                  ),

                  label: const Text(
                    'EDIT PROFILE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.red,
                    foregroundColor:
                        Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ------------------------------------------------
              // LOGOUT
              // ------------------------------------------------

              SizedBox(
                width: double.infinity,
                height: 50,

                child: OutlinedButton.icon(
                  onPressed: _logout,

                  icon: const Icon(
                    Icons.logout,
                  ),

                  label: const Text(
                    'LOGOUT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.red,
                    side: const BorderSide(
                      color: Colors.red,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EDIT DONOR PROFILE SCREEN
// ============================================================

class EditDonorProfileScreen
    extends StatefulWidget {
  const EditDonorProfileScreen({super.key});

  @override
  State<EditDonorProfileScreen> createState() =>
      _EditDonorProfileScreenState();
}

class _EditDonorProfileScreenState
    extends State<EditDonorProfileScreen> {
  final TextEditingController nameController =
      TextEditingController();

  final TextEditingController locationController =
      TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  bool availability = true;

  // ------------------------------------------------------------
  // LOAD CURRENT PROFILE
  // ------------------------------------------------------------

  Future<void> _loadProfile() async {
    try {
      final User? user =
          FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
        });

        return;
      }

      final DocumentSnapshot<Map<String, dynamic>>
          document =
          await FirebaseFirestore.instance
              .collection('donors')
              .doc(user.uid)
              .get();

      if (!mounted) return;

      if (!document.exists) {
        setState(() {
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Donor profile not found.',
            ),
          ),
        );

        return;
      }

      final Map<String, dynamic> data =
          document.data() ?? {};

      nameController.text =
          data['name']?.toString() ?? '';

      locationController.text =
          data['location']?.toString() ?? '';

      availability =
          data['availability'] == true;

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Edit profile load error: $e',
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to load profile.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // SAVE PROFILE
  // ------------------------------------------------------------

  Future<void> _saveProfile() async {
    final String name =
        nameController.text.trim();

    final String location =
        locationController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your full name.',
          ),
        ),
      );

      return;
    }

    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your location.',
          ),
        ),
      );

      return;
    }

    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'User session not found.',
          ),
        ),
      );

      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .update({
        'name': name,
        'location': location,
        'availability': availability,
      });

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile updated successfully.',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint(
        'Save profile error: $e',
      );

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to update your profile.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadProfile();
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Edit Profile',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),

        body: const Center(
          child: CircularProgressIndicator(
            color: Colors.red,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // --------------------------------------------------
            // HEADER
            // --------------------------------------------------

            const Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor:
                        Colors.red,
                    child: Icon(
                      Icons.edit,
                      size: 45,
                      color: Colors.white,
                    ),
                  ),

                  SizedBox(height: 15),

                  Text(
                    'Edit Your Profile',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --------------------------------------------------
            // FULL NAME
            // --------------------------------------------------

            const Text(
              'Full Name',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: nameController,

              textInputAction:
                  TextInputAction.next,

              decoration: InputDecoration(
                hintText:
                    'Enter your full name',

                prefixIcon: const Icon(
                  Icons.person,
                  color: Colors.red,
                ),

                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // LOCATION
            // --------------------------------------------------

            const Text(
              'Location',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller:
                  locationController,

              textInputAction:
                  TextInputAction.done,

              decoration: InputDecoration(
                hintText:
                    'Enter your location',

                prefixIcon: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                ),

                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 25),

            // --------------------------------------------------
            // AVAILABILITY
            // --------------------------------------------------

            Card(
              child: SwitchListTile(
                value: availability,

                onChanged: isSaving
                    ? null
                    : (bool value) {
                        setState(() {
                          availability =
                              value;
                        });
                      },

                activeThumbColor:
                    Colors.red,

                title: const Text(
                  'Available for Blood Donation',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                subtitle: Text(
                  availability
                      ? 'You can receive suitable emergency alerts.'
                      : 'You will not be considered available for alerts.',
                ),

                secondary: Icon(
                  availability
                      ? Icons.check_circle
                      : Icons.cancel,

                  color: availability
                      ? Colors.green
                      : Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // INFORMATION
            // --------------------------------------------------

            Card(
              color: Colors.red.shade50,

              child: const Padding(
                padding: EdgeInsets.all(16),

                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red,
                    ),

                    SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Your blood group and phone number '
                        'cannot be changed from this screen. '
                        'Contact an authorized Blood Link '
                        'organization if those details need '
                        'to be corrected.',
                        style: TextStyle(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // --------------------------------------------------
            // SAVE BUTTON
            // --------------------------------------------------

            SizedBox(
              width: double.infinity,
              height: 52,

              child: ElevatedButton.icon(
                onPressed:
                    isSaving
                        ? null
                        : _saveProfile,

                icon: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.save,
                      ),

                label: Text(
                  isSaving
                      ? 'SAVING...'
                      : 'SAVE CHANGES',

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.red,
                  foregroundColor:
                      Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // CANCEL
            // --------------------------------------------------

            SizedBox(
              width: double.infinity,
              height: 50,

              child: OutlinedButton(
                onPressed: isSaving
                    ? null
                    : () {
                        Navigator.pop(
                          context,
                        );
                      },

                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      Colors.red,

                  side:
                      const BorderSide(
                    color: Colors.red,
                  ),
                ),

                child: const Text(
                  'CANCEL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
// ============================================================
// DONOR HOME SCREEN
// ============================================================

class DonorHomeScreen extends StatelessWidget {
  const DonorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blood Link'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            const Icon(
              Icons.bloodtype,
              size: 75,
              color: Colors.red,
            ),

            const SizedBox(height: 10),

            const Text(
              'Donor Dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Your blood can save a life.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 25),

            // ------------------------------------------------
            // EMERGENCY ALERT
            // ------------------------------------------------

            _dashboardCard(
              context,
              icon: Icons.warning_amber_rounded,
              title: 'Emergency Blood Alerts',
              subtitle:
                  'Receive urgent requests when Blood Link selects you as a priority donor.',
              iconColor: Colors.red,
              screen: const EmergencyAlertScreen(),
            ),

            // ============================================================
            // NEED BLOOD
            // ============================================================

           _dashboardCard(
             context,
             icon: Icons.emergency,
             title: 'Need Blood?',
             subtitle:
             'Raise an emergency blood request for yourself or your family.',
             iconColor: Colors.red,
             screen: const NeedBloodScreen(),
            ),

            // ------------------------------------------------
            // DONATION REMINDER
            // ------------------------------------------------

            _dashboardCard(
              context,
              icon: Icons.notifications_active,
              title: 'Donation Reminder',
              subtitle:
                  'Blood Link remembers your donation date and reminds you when your next donation period approaches.',
              iconColor: Colors.orange,
              screen: const
              DonationReminderScreen(),
            ),

            // ------------------------------------------------
            // DONATION HISTORY
            // ------------------------------------------------

            _dashboardCard(
              context,
              icon: Icons.history,
              title: 'Donation History',
              subtitle:
                  'View the dates and verification status of your previous donations.',
              iconColor: Colors.blue,
              screen: const DonationHistoryScreen(),
            ),

            // ------------------------------------------------
            // PROFILE
            // ------------------------------------------------

            _dashboardCard(
              context,
              icon: Icons.person,
              title: 'My Profile',
              subtitle:
                  'View your donor information and account details.',
              iconColor: Colors.green,
              screen: const DonorProfileScreen(),
            ),

            // ------------------------------------------------
            // REWARDS
            // ------------------------------------------------

            _dashboardCard(
              context,
              icon: Icons.emoji_events,
              title: 'My Rewards',
              subtitle:
                  'View your verified donation rewards and achievements.',
              iconColor: Colors.amber,
              screen: const RewardsScreen(),
            ),

            const SizedBox(height: 20),

            // ------------------------------------------------
            // PRIVACY MESSAGE
            // ------------------------------------------------

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: const [
                    Icon(
                      Icons.security,
                      color: Colors.green,
                      size: 35,
                    ),

                    SizedBox(height: 10),

                    Text(
                      'Your Privacy Matters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 8),

                    Text(
                      'Your donor information is private. '
                      'Blood Link does not display a public donor list to patients or requesters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Widget screen,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),

        leading: CircleAvatar(
          backgroundColor: iconColor,
          child: Icon(
            icon,
            color: Colors.white,
          ),
        ),

        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),

        subtitle: Text(subtitle),

        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 18,
        ),

        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => screen,
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// DONATION REMINDER SCREEN
// ============================================================

// ============================================================
// DONATION REMINDER SCREEN
// ============================================================

// ============================================================
// DONATION REMINDER SCREEN
// ============================================================

class DonationReminderScreen extends StatefulWidget {
  const DonationReminderScreen({super.key});

  @override
  State<DonationReminderScreen> createState() =>
      _DonationReminderScreenState();
}

class _DonationReminderScreenState
    extends State<DonationReminderScreen> {
  Timer? _countdownTimer;

  DateTime? _lastDonationDate;
  DateTime? _nextReminderDate;

  Duration _remaining = Duration.zero;

  bool _loading = true;
  bool _updatingFirestore = false;

  String? _errorMessage;

  // App reminder interval.
  // This is only an app reminder setting.
  // It does NOT determine medical eligibility.
  static const int reminderDays = 90;

  @override
  void initState() {
    super.initState();

    _loadDonationData();

    // Update countdown and status every second.
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _updateReminderState();
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // LOAD DONATION DATA
  // ============================================================

  Future<void> _loadDonationData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Please login to view your donation reminder.';
      });

      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage = 'Donor profile not found.';
        });

        return;
      }

      final data = doc.data();

      if (data == null) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _errorMessage =
              'Unable to read donor information.';
        });

        return;
      }

      final dynamic rawDate =
          data['lastDonationDate'];

      DateTime? donationDate;

      // Firestore Timestamp
      if (rawDate is Timestamp) {
        donationDate = rawDate.toDate();
      }

      // String date support
      else if (rawDate is String &&
          rawDate.trim().isNotEmpty) {
        donationDate = DateTime.tryParse(
          rawDate.trim(),
        );
      }

      // No donation date
      if (donationDate == null) {
        if (!mounted) return;

        setState(() {
          _lastDonationDate = null;
          _nextReminderDate = null;
          _remaining = Duration.zero;
          _loading = false;
          _errorMessage = null;
        });

        await _saveReminderStatus(
          'WAITING FOR DONATION',
        );

        return;
      }

      final nextDate = donationDate.add(
        const Duration(days: reminderDays),
      );

      if (!mounted) return;

      setState(() {
        _lastDonationDate = donationDate;
        _nextReminderDate = nextDate;
        _loading = false;
        _errorMessage = null;
      });

      await _updateReminderState();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Unable to load donation information.\n$e';
      });
    }
  }

  // ============================================================
  // AUTOMATIC STATUS
  // ============================================================

  String get _reminderStatus {
    if (_lastDonationDate == null) {
      return 'WAITING FOR DONATION';
    }

    if (_nextReminderDate == null) {
      return 'WAITING FOR DONATION';
    }

    final now = DateTime.now();

    if (now.isAfter(_nextReminderDate!) ||
        now.isAtSameMomentAs(_nextReminderDate!)) {
      return 'DUE';
    }

    return 'ACTIVE';
  }

  // ============================================================
  // STATUS COLOR
  // ============================================================

  Color get _statusColor {
    switch (_reminderStatus) {
      case 'DUE':
        return Colors.green;

      case 'ACTIVE':
        return Colors.orange;

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // STATUS ICON
  // ============================================================

  IconData get _statusIcon {
    switch (_reminderStatus) {
      case 'DUE':
        return Icons.check_circle;

      case 'ACTIVE':
        return Icons.notifications_active;

      default:
        return Icons.help_outline;
    }
  }

  // ============================================================
  // UPDATE COUNTDOWN + FIRESTORE STATUS
  // ============================================================

  Future<void> _updateReminderState() async {
    if (!mounted) return;

    if (_nextReminderDate == null) {
      setState(() {
        _remaining = Duration.zero;
      });

      await _saveReminderStatus(
        'WAITING FOR DONATION',
      );

      return;
    }

    final now = DateTime.now();

    final difference =
        _nextReminderDate!.difference(now);

    if (!mounted) return;

    setState(() {
      _remaining = difference.isNegative
          ? Duration.zero
          : difference;
    });

    final status = _reminderStatus;

    await _saveReminderStatus(status);
  }

  // ============================================================
  // SAVE STATUS TO FIRESTORE
  // ============================================================

  Future<void> _saveReminderStatus(
    String status,
  ) async {
    if (_updatingFirestore) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    _updatingFirestore = true;

    try {
      await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .update({
        'reminderStatus': status,
        'reminderUpdatedAt':
            FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Do not interrupt the reminder UI
      // if Firestore status update fails.
    } finally {
      _updatingFirestore = false;
    }
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }

  // ============================================================
  // FORMAT COUNTDOWN
  // ============================================================

  String _formatDuration(Duration duration) {
    final days = duration.inDays;

    final hours =
        duration.inHours.remainder(24);

    final minutes =
        duration.inMinutes.remainder(60);

    final seconds =
        duration.inSeconds.remainder(60);

    return '${days}d '
        '${hours.toString().padLeft(2, '0')}h '
        '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }

  // ============================================================
  // INFO CARD
  // ============================================================

  Widget _infoCard({
    required Widget child,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: child,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Donation Reminder',
        ),
      ),
      body: _buildBody(),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.orange,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _infoCard(
            color: Colors.red.shade50,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 50,
                ),

                const SizedBox(height: 12),

                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 15),

                ElevatedButton(
                  onPressed: _loadDonationData,
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDonationData,
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            // ==================================================
            // HEADER
            // ==================================================

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius:
                    BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Colors.orange.shade700,
                    size: 60,
                  ),

                  const SizedBox(height: 15),

                  const Text(
                    'Never Forget Your Donation Date',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Blood Link uses your donation history '
                    'to calculate and update your reminder '
                    'status automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ==================================================
            // LAST DONATION
            // ==================================================

            _infoCard(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Last Donation',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    _lastDonationDate == null
                        ? 'No donation recorded'
                        : _formatDate(
                            _lastDonationDate!,
                          ),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ==================================================
            // NEXT REMINDER
            // ==================================================

            _infoCard(
              color: Colors.orange.shade50,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next Reminder Date',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    _nextReminderDate == null
                        ? 'Waiting for donation date'
                        : _formatDate(
                            _nextReminderDate!,
                          ),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ==================================================
            // LIVE COUNTDOWN
            // ==================================================

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _reminderStatus == 'DUE'
                    ? Colors.green.shade50
                    : _reminderStatus == 'ACTIVE'
                        ? Colors.blue.shade50
                        : Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    _statusIcon,
                    color: _statusColor,
                    size: 42,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    _reminderStatus == 'DUE'
                        ? 'REMINDER DATE REACHED'
                        : _reminderStatus ==
                                'ACTIVE'
                            ? 'TIME UNTIL REMINDER'
                            : 'DONATION DATE REQUIRED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 14,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _reminderStatus == 'DUE'
                        ? 'Reminder is due'
                        : _reminderStatus ==
                                'ACTIVE'
                            ? _formatDuration(
                                _remaining,
                              )
                            : '--',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 25,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ==================================================
            // AUTOMATIC STATUS
            // ==================================================

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _reminderStatus == 'DUE'
                    ? Colors.green.shade50
                    : _reminderStatus ==
                            'ACTIVE'
                        ? Colors.orange.shade50
                        : Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIcon,
                    color: _statusColor,
                    size: 35,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reminder Status',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          _reminderStatus,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // STATUS FLOW
            // ==================================================

            _infoCard(
              color: Colors.grey.shade100,
              child: Column(
                children: [
                  const Icon(
                    Icons.sync,
                    color: Colors.grey,
                    size: 35,
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Automatic Reminder Flow',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _lastDonationDate == null
                        ? 'No donation date → '
                          'WAITING FOR DONATION'
                        : _reminderStatus ==
                                'ACTIVE'
                            ? 'Before reminder date → '
                              'ACTIVE'
                            : 'Reminder date reached → '
                              'DUE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // MEDICAL INFORMATION
            // ==================================================

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.grey,
                    size: 35,
                  ),

                  SizedBox(height: 10),

                  Text(
                    'The reminder is calculated from the '
                    'donation date stored in your Blood Link '
                    'profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  SizedBox(height: 10),

                  Text(
                    'The reminder interval is an app '
                    'scheduling setting and does not '
                    'independently determine medical '
                    'eligibility. Always follow blood-bank '
                    'and medical guidance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
// ============================================================
// DONATION HISTORY SCREEN
// ============================================================
// ============================================================
// DONATION HISTORY SCREEN
// ============================================================

class DonationHistoryScreen extends StatefulWidget {
  const DonationHistoryScreen({super.key});

  @override
  State<DonationHistoryScreen> createState() =>
      _DonationHistoryScreenState();
}

class _DonationHistoryScreenState
    extends State<DonationHistoryScreen> {
  // ------------------------------------------------------------
  // FORMAT DATE
  // ------------------------------------------------------------

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'Date not available';
    }

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }

    if (date == null) {
      return 'Date not available';
    }

    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthName(date.month)} '
        '${date.year}';
  }

  // ------------------------------------------------------------
  // MONTH NAME
  // ------------------------------------------------------------

  String _monthName(int month) {
    const List<String> months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  // ------------------------------------------------------------
  // REAL-TIME DONATION HISTORY
  // ------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>>
      _donationHistoryStream() {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('donors')
        .doc(user.uid)
        .collection('donationHistory')
        .orderBy(
          'donationDate',
          descending: true,
        )
        .snapshots();
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Donation History',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),

      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _donationHistoryStream(),

        builder: (context, snapshot) {
          // ----------------------------------------------------
          // LOADING
          // ----------------------------------------------------

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.red,
              ),
            );
          }

          // ----------------------------------------------------
          // ERROR
          // ----------------------------------------------------

          if (snapshot.hasError) {
            debugPrint(
              'Donation history stream error: '
              '${snapshot.error}',
            );

            return _errorView();
          }

          // ----------------------------------------------------
          // NO USER
          // ----------------------------------------------------

          if (!snapshot.hasData) {
            return _emptyHistory();
          }

          final List<
              QueryDocumentSnapshot<
                  Map<String, dynamic>>> documents =
              snapshot.data!.docs;

          // ----------------------------------------------------
          // EMPTY HISTORY
          // ----------------------------------------------------

          if (documents.isEmpty) {
            return _emptyHistory();
          }

          // ----------------------------------------------------
          // REAL-TIME HISTORY LIST
          // ----------------------------------------------------

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            physics:
                const AlwaysScrollableScrollPhysics(),
            itemCount: documents.length,

            itemBuilder: (context, index) {
              final QueryDocumentSnapshot<
                      Map<String, dynamic>>
                  document =
                  documents[index];

              final Map<String, dynamic> donation =
                  document.data();

              donation['id'] = document.id;

              return _donationCard(
                donation,
              );
            },
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------
  // ERROR VIEW
  // ------------------------------------------------------------

  Widget _errorView() {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.all(20),

      children: [
        const SizedBox(height: 80),

        const Icon(
          Icons.error_outline,
          size: 80,
          color: Colors.red,
        ),

        const SizedBox(height: 20),

        const Text(
          'Unable to Load Donation History',
          textAlign: TextAlign.center,

          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        const Text(
          'Please check your internet connection '
          'and try again.',
          textAlign: TextAlign.center,

          style: TextStyle(
            color: Colors.grey,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 25),

        Center(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {});
            },

            icon: const Icon(
              Icons.refresh,
            ),

            label: const Text(
              'Retry',
            ),

            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // EMPTY HISTORY
  // ------------------------------------------------------------

  Widget _emptyHistory() {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.all(20),

      children: [
        const SizedBox(height: 80),

        const Icon(
          Icons.bloodtype_outlined,
          size: 80,
          color: Colors.grey,
        ),

        const SizedBox(height: 20),

        const Text(
          'No Donation Records Yet',
          textAlign: TextAlign.center,

          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        const Text(
          'Your verified blood donation records '
          'will appear here after they are added '
          'by an authorized Blood Link organization.',
          textAlign: TextAlign.center,

          style: TextStyle(
            color: Colors.grey,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 30),

        Card(
          color: Colors.red.shade50,

          child: const Padding(
            padding: EdgeInsets.all(18),

            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.red,
                ),

                SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'Donation records are verified by '
                    'authorized organizations. Self-reported '
                    'donations are not treated as verified records.',
                    style: TextStyle(
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // DONATION CARD
  // ------------------------------------------------------------

  Widget _donationCard(
    Map<String, dynamic> donation,
  ) {
    final String date =
        _formatDate(
      donation['donationDate'],
    );

    final String hospital =
        donation['hospitalName']?.toString() ??
            'Blood donation';

    final String status =
        donation['status']?.toString() ??
            'Verified';

    final bool verified =
        status.toLowerCase() == 'verified';

    return Card(
      elevation: 3,

      margin: const EdgeInsets.only(
        bottom: 12,
      ),

      child: ListTile(
        contentPadding:
            const EdgeInsets.all(12),

        leading: const CircleAvatar(
          backgroundColor: Colors.red,

          child: Icon(
            Icons.bloodtype,
            color: Colors.white,
          ),
        ),

        title: const Text(
          'Blood Donation',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 6),

          child: Text(
            '$date\n$hospital',
          ),
        ),

        trailing: Icon(
          verified
              ? Icons.verified
              : Icons.info_outline,

          color: verified
              ? Colors.green
              : Colors.orange,
        ),
      ),
    );
  }
}
// ============================================================
// EMERGENCY ALERT SCREEN
// ============================================================

class EmergencyAlertScreen extends StatelessWidget {
  const EmergencyAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Emergency Blood Alert',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'Please login again.',
            style: TextStyle(
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Blood Alert',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requestDonors')
            .where(
              'donorId',
              isEqualTo: user.uid,
            )
            .where(
              'response',
              isEqualTo: 'pending',
            )
            .snapshots(),
        builder: (
          context,
          assignmentSnapshot,
        ) {
          // ====================================================
          // LOADING
          // ====================================================

          if (assignmentSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.red,
              ),
            );
          }

          // ====================================================
          // ERROR
          // ====================================================

          if (assignmentSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Unable to load emergency alerts.\n\n'
                  '${assignmentSnapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          // ====================================================
          // GET ASSIGNMENTS
          // ====================================================

          final List<QueryDocumentSnapshot>
              assignments =
              assignmentSnapshot.data?.docs ?? [];

          if (assignments.isEmpty) {
            return _noEmergencyRequests();
          }

          // ====================================================
          // GET FIRST PENDING ASSIGNMENT
          // ====================================================

          final QueryDocumentSnapshot assignment =
              assignments.first;

          final Map<String, dynamic> assignmentData =
              assignment.data()
                  as Map<String, dynamic>;

          final String requestId =
              assignmentData['requestId']
                      ?.toString() ??
                  '';

          if (requestId.isEmpty) {
            return _errorMessage(
              'Emergency assignment does not contain a request ID.',
            );
          }

          // ====================================================
          // IMPORTANT
          //
          // Emergency information is read directly from
          // requestDonors.
          //
          // We do NOT read emergencyRequests here.
          // ====================================================

          return _buildEmergencyAlert(
            context,
            assignment.id,
            requestId,
            assignmentData,
          );
        },
      ),
    );
  }

  // ============================================================
  // EMERGENCY ALERT UI
  // ============================================================

  Widget _buildEmergencyAlert(
    BuildContext context,
    String assignmentId,
    String requestId,
    Map<String, dynamic> data,
  ) {
    final String bloodGroup =
        data['bloodGroup']?.toString() ??
            'Unknown';

    final String patientName =
        data['patientName']?.toString() ??
            'Patient';

    final String hospitalName =
        data['hospitalName']?.toString() ??
            'Hospital';

    final String hospitalLocation =
        data['hospitalLocation']?.toString() ??
            'Location';

    final String urgency =
        data['urgency']?.toString() ??
            'Normal';

    final String units =
        data['unitsRequired']?.toString() ??
            '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),

      child: Column(
        children: [

          // ====================================================
          // HEADER
          // ====================================================

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),

            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius:
                  BorderRadius.circular(20),

              border: Border.all(
                color: Colors.red.shade200,
                width: 2,
              ),
            ),

            child: Column(
              children: [

                const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 65,
                ),

                const SizedBox(height: 12),

                const Text(
                  'EMERGENCY BLOOD REQUEST',
                  textAlign: TextAlign.center,

                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                    color: Colors.red,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'You have been selected as a priority donor.',
                  textAlign: TextAlign.center,

                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================
          // BLOOD GROUP
          // ====================================================

          _alertInfoCard(
            Icons.bloodtype,
            'Blood Group',
            bloodGroup,
          ),

          // ====================================================
          // PATIENT
          // ====================================================

          _alertInfoCard(
            Icons.person,
            'Patient',
            patientName,
          ),

          // ====================================================
          // HOSPITAL
          // ====================================================

          _alertInfoCard(
            Icons.local_hospital,
            'Hospital',
            hospitalName,
          ),

          // ====================================================
          // LOCATION
          // ====================================================

          _alertInfoCard(
            Icons.location_on,
            'Location',
            hospitalLocation,
          ),

          // ====================================================
          // UNITS
          // ====================================================

          _alertInfoCard(
            Icons.bloodtype_outlined,
            'Units Required',
            units,
          ),

          // ====================================================
          // URGENCY
          // ====================================================

          _alertInfoCard(
            Icons.priority_high,
            'Urgency',
            urgency.toUpperCase(),
          ),

          const SizedBox(height: 20),

          const Text(
            'Your response helps Blood Link decide whether '
            'to continue with the next suitable donor.',
            textAlign: TextAlign.center,

            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================
          // I CAN HELP
          // ====================================================

          SizedBox(
            width: double.infinity,
            height: 55,

            child: ElevatedButton.icon(
              onPressed: () {
                _sendResponse(
                  context,
                  assignmentId,
                  requestId,
                  'accepted',
                );
              },

              icon: const Icon(
                Icons.favorite,
              ),

              label: const Text(
                'I CAN HELP',
                style: TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.red,
                foregroundColor:
                    Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ====================================================
          // I CAN'T HELP
          // ====================================================

          SizedBox(
            width: double.infinity,
            height: 55,

            child: OutlinedButton.icon(
              onPressed: () {
                _sendResponse(
                  context,
                  assignmentId,
                  requestId,
                  'declined',
                );
              },

              icon: const Icon(
                Icons.close,
              ),

              label: const Text(
                "I CAN'T HELP",
                style: TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    Colors.red,

                side: const BorderSide(
                  color: Colors.red,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================
          // PRIVACY
          // ====================================================

          Container(
            padding:
                const EdgeInsets.all(16),

            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  BorderRadius.circular(15),
            ),

            child: const Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Icon(
                  Icons.lock,
                  color: Colors.grey,
                ),

                SizedBox(width: 10),

                Expanded(
                  child: Text(
                    'Donor information is private. '
                    'The requester does not see a public donor list.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEND DONOR RESPONSE
  // ============================================================

  Future<void> _sendResponse(
    BuildContext context,
    String assignmentId,
    String requestId,
    String response,
  ) async {
    final User? user =
        FirebaseAuth.instance.currentUser;

    // ==========================================================
    // CHECK LOGIN
    // ==========================================================

    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please login again.',
          ),
        ),
      );

      return;
    }

    try {
      final FirebaseFirestore firestore =
          FirebaseFirestore.instance;

      // ========================================================
      // GET ASSIGNMENT
      // ========================================================

      final DocumentReference<
          Map<String, dynamic>> assignmentRef =
          firestore
              .collection('requestDonors')
              .doc(assignmentId);

      final DocumentSnapshot<
          Map<String, dynamic>> assignmentSnapshot =
          await assignmentRef.get();

      if (!assignmentSnapshot.exists) {
        throw Exception(
          'This emergency donor assignment no longer exists.',
        );
      }

      final Map<String, dynamic> assignmentData =
          assignmentSnapshot.data() ?? {};

      // ========================================================
      // VERIFY DONOR
      // ========================================================

      final String assignedDonorId =
          assignmentData['donorId']
                  ?.toString() ??
              '';

      if (assignedDonorId.isEmpty) {
        throw Exception(
          'This donor assignment does not contain a donor ID.',
        );
      }

      if (assignedDonorId != user.uid) {
        throw Exception(
          'This emergency request is not assigned '
          'to your donor account.',
        );
      }

      // ========================================================
      // VERIFY REQUEST
      // ========================================================

      final String assignedRequestId =
          assignmentData['requestId']
                  ?.toString() ??
              '';

      if (assignedRequestId != requestId) {
        throw Exception(
          'Emergency request mismatch.',
        );
      }

      // ========================================================
      // GET DONOR PROFILE
      // ========================================================

      final DocumentSnapshot<
          Map<String, dynamic>> donorSnapshot =
          await firestore
              .collection('donors')
              .doc(user.uid)
              .get();

      if (!donorSnapshot.exists) {
        throw Exception(
          'Your donor profile could not be found.',
        );
      }

      final Map<String, dynamic> donorData =
          donorSnapshot.data() ?? {};

      final String donorName =
          donorData['name']?.toString() ??
              '';

      final String donorPhone =
          donorData['phone']?.toString() ??
              '';

      final String donorBloodGroup =
          donorData['bloodGroup']
                  ?.toString() ??
              '';

      final String donorLocation =
          donorData['location']?.toString() ??
              '';

      // ========================================================
      // SAVE DONOR INFORMATION
      //
      // THIS FIXES "UNKNOWN DONOR" ON NGO PAGE.
      // ========================================================

      await assignmentRef.update({
        'donorId': user.uid,

        'donorName': donorName,

        'donorPhone': donorPhone,

        'bloodGroup':
            donorBloodGroup,

        'location':
            donorLocation,

        'response':
            response,

        'respondedAt':
            FieldValue.serverTimestamp(),

        'accepted':
            response == 'accepted',

        'declined':
            response == 'declined',
      });

      // ========================================================
      // SUCCESS
      // ========================================================

      if (!context.mounted) {
        return;
      }

      final bool accepted =
          response == 'accepted';

      await showDialog(
        context: context,

        builder: (dialogContext) {
          return AlertDialog(

            title: Text(
              accepted
                  ? 'Thank You ❤️'
                  : 'Response Recorded',
            ),

            content: Text(
              accepted
                  ? 'Your willingness to help has been '
                    'sent to the authorized organization. '
                    'Please wait for further instructions.'
                  : 'No problem. Your response has been '
                    'recorded. Blood Link can proceed '
                    'with another suitable donor.',
            ),

            actions: [

              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },

                child: const Text(
                  'OK',
                ),
              ),
            ],
          );
        },
      );

    } catch (e) {

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send response: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // NO EMERGENCY REQUESTS
  // ============================================================

  Widget _noEmergencyRequests() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            Icon(
              Icons.notifications_none,
              size: 80,
              color: Colors.grey.shade400,
            ),

            const SizedBox(height: 20),

            const Text(
              'No Emergency Alerts',
              style: TextStyle(
                fontSize: 21,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'When you are selected as a suitable donor '
              'for an emergency request, it will appear here.',

              textAlign: TextAlign.center,

              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  Widget _errorMessage(
    String message,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Text(
          message,
          textAlign: TextAlign.center,

          style: const TextStyle(
            color: Colors.red,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // INFO CARD
  // ============================================================

  Widget _alertInfoCard(
    IconData icon,
    String title,
    String value,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),

      padding:
          const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(15),

        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(
              alpha: 0.15,
            ),
            blurRadius: 8,
            offset:
                const Offset(0, 3),
          ),
        ],
      ),

      child: Row(
        children: [

          CircleAvatar(
            backgroundColor:
                Colors.red.shade50,

            child: Icon(
              icon,
              color: Colors.red,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Text(
                  title,

                  style:
                      const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,

                  style:
                      const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}// REWARDS SCREEN
// ============================================================

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rewards'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.red,
                    child: Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Blood Hero',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thank you for helping save lives!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _rewardCard(
                    Icons.stars,
                    '200',
                    'Points',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _rewardCard(
                    Icons.bloodtype,
                    '2',
                    'Donations',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.grey.shade200,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🏆 Achievement',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Blood Hero Badge',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Awarded for verified blood donations through Blood Link.',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                'Rewards shown here are prototype data. In the future, verified donations can automatically update points and achievements.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard(
    IconData icon,
    String number,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.red,
            size: 35,
          ),
          const SizedBox(height: 8),
          Text(
            number,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// ORGANIZATION / NGO / HOSPITAL HOME SCREEN
// ============================================================
class OrganizationHomeScreen extends StatelessWidget {
  const OrganizationHomeScreen({super.key});

  // ============================================================
  // CURRENT MONTH NAME
  // ============================================================

  String _currentMonthName() {
    const List<String> months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[DateTime.now().month - 1];
  }

  // ============================================================
  // MONTHLY DONATION STREAM
  // ============================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
      _monthlyDonationStream() {
    final DateTime now = DateTime.now();

    final DateTime startOfMonth = DateTime(
      now.year,
      now.month,
      1,
    );

    final DateTime startOfNextMonth = DateTime(
      now.month == 12
          ? now.year + 1
          : now.year,
      now.month == 12
          ? 1
          : now.month + 1,
      1,
    );

    return FirebaseFirestore.instance
        .collectionGroup('donationHistory')
        .where(
          'donationDate',
          isGreaterThanOrEqualTo:
              Timestamp.fromDate(startOfMonth),
        )
        .where(
          'donationDate',
          isLessThan:
              Timestamp.fromDate(startOfNextMonth),
        )
        .snapshots();
  }

  // ============================================================
  // MONTHLY DONATION STATISTICS
  // ============================================================

  Widget _monthlyDonationStatistics(
    BuildContext context,
  ) {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: _monthlyDonationStream(),

      builder: (context, snapshot) {
        // --------------------------------------------------------
        // LOADING
        // --------------------------------------------------------

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius:
                  BorderRadius.circular(18),
              border: Border.all(
                color: Colors.red.shade100,
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Colors.red,
              ),
            ),
          );
        }

        // --------------------------------------------------------
        // ERROR
        // --------------------------------------------------------

        if (snapshot.hasError) {
          debugPrint(
            'Monthly donation statistics error: '
            '${snapshot.error}',
          );

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius:
                  BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red,
                ),

                SizedBox(width: 10),

                Expanded(
                  child: Text(
                    'Unable to load donation statistics.',
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // --------------------------------------------------------
        // DOCUMENTS
        // --------------------------------------------------------

        final List<
                QueryDocumentSnapshot<
                    Map<String, dynamic>>>
            documents =
            snapshot.data?.docs ?? [];

        // --------------------------------------------------------
        // COUNT VERIFIED / COMPLETED DONATIONS
        // --------------------------------------------------------

        int completedDonations = 0;

        for (final document in documents) {
          final Map<String, dynamic> data =
              document.data();

          final String status =
              data['status']
                      ?.toString()
                      .toLowerCase()
                      .trim() ??
                  'verified';

          if (status == 'verified' ||
              status == 'completed') {
            completedDonations++;
          }
        }

        // --------------------------------------------------------
        // STATISTICS CARD
        // --------------------------------------------------------

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius:
                BorderRadius.circular(18),
            border: Border.all(
              color: Colors.red.shade100,
            ),
          ),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              // --------------------------------------------------
              // TITLE
              // --------------------------------------------------

              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.all(10),

                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),

                    child: const Icon(
                      Icons.bar_chart,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(width: 12),

                  const Expanded(
                    child: Text(
                      'Donation Statistics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  // Real-time indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius:
                          BorderRadius.circular(20),
                    ),

                    child: const Row(
                      mainAxisSize:
                          MainAxisSize.min,

                      children: [
                        Icon(
                          Icons.circle,
                          size: 7,
                          color: Colors.green,
                        ),

                        SizedBox(width: 5),

                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // MONTHLY COUNT
              // --------------------------------------------------

              Container(
                width: double.infinity,

                padding:
                    const EdgeInsets.symmetric(
                  vertical: 22,
                  horizontal: 15,
                ),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(15),
                ),

                child: Column(
                  children: [

                    Text(
                      '$completedDonations',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight:
                            FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Donations Completed',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _currentMonthName(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // --------------------------------------------------
              // INFORMATION
              // --------------------------------------------------

              Row(
                children: [
                  const Icon(
                    Icons.sync,
                    size: 16,
                    color: Colors.green,
                  ),

                  const SizedBox(width: 7),

                  Expanded(
                    child: Text(
                      'Automatically updated from verified '
                      'donation records.',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blood Link',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        backgroundColor: Colors.red,
        foregroundColor: Colors.white,

        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout,
            ),

            tooltip: 'Logout',

            onPressed: () async {
              await FirebaseAuth.instance
                  .signOut();

              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,

                MaterialPageRoute(
                  builder: (context) =>
                      const LoginScreen(),
                ),

                (route) => false,
              );
            },
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              // ==================================================
              // HEADER
              // ==================================================

              Container(
                width: double.infinity,

                padding:
                    const EdgeInsets.all(22),

                decoration: BoxDecoration(
                  color: Colors.red.shade50,

                  borderRadius:
                      BorderRadius.circular(20),

                  border: Border.all(
                    color: Colors.red.shade100,
                  ),
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    const Icon(
                      Icons.local_hospital,
                      color: Colors.red,
                      size: 45,
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Organization Dashboard',

                      style: TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Manage blood requests and donor information.',

                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),

                    if (currentUser?.email != null) ...[
                      const SizedBox(height: 10),

                      Text(
                        currentUser!.email!,

                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // ==================================================
              // EMERGENCY MANAGEMENT
              // ==================================================

              const Text(
                'Emergency Management',

                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,

                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) =>
                            const EmergencyRequestScreen(),
                      ),
                    );
                  },

                  icon: const Icon(
                    Icons.emergency,
                  ),

                  label: const Padding(
                    padding:
                        EdgeInsets.symmetric(
                      vertical: 16,
                    ),

                    child: Text(
                      'RAISE EMERGENCY BLOOD REQUEST',

                      style: TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.red,

                    foregroundColor:
                        Colors.white,

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // ==================================================
              // DONOR DIRECTORY
              // ==================================================

              SizedBox(
                width: double.infinity,

                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) =>
                            const DonorDirectoryScreen(),
                      ),
                    );
                  },

                  icon: const Icon(
                    Icons.people,
                  ),

                  label: const Padding(
                    padding:
                        EdgeInsets.symmetric(
                      vertical: 15,
                    ),

                    child: Text(
                      'SEE ALL DONORS',

                      style: TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.red,

                    side:
                        const BorderSide(
                      color: Colors.red,
                    ),

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // ==================================================
              // DONATION STATISTICS
              // ==================================================

              const Text(
                'Donation Statistics',

                style: TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              _monthlyDonationStatistics(
                context,
              ),

              const SizedBox(height: 30),

              // ==================================================
              // ACTIVE EMERGENCY REQUESTS
              // ==================================================

              const Text(
                'Active Emergency Requests',

                style: TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Requests raised by organizations and donors.',

                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 12),

              // ==================================================
              // ALL SEARCHING REQUESTS
              // ==================================================

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore
                    .instance
                    .collection(
                      'emergencyRequests',
                    )
                    .where(
                      'status',
                      isEqualTo: 'Searching',
                    )
                    .snapshots(),

                builder:
                    (context, snapshot) {

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding:
                            EdgeInsets.all(25),

                        child:
                            CircularProgressIndicator(
                          color: Colors.red,
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Container(
                      width:
                          double.infinity,

                      padding:
                          const EdgeInsets.all(
                        16,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            Colors.red.shade50,

                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                      ),

                      child: Text(
                        'Unable to load emergency requests.\n\n'
                        '${snapshot.error}',

                        style:
                            const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    );
                  }

                  final requests =
                      snapshot.data?.docs ??
                          [];

                  if (requests.isEmpty) {
                    return Container(
                      width:
                          double.infinity,

                      padding:
                          const EdgeInsets.all(
                        25,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            Colors.grey.shade100,

                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                      ),

                      child: const Column(
                        children: [
                          Icon(
                            Icons
                                .check_circle_outline,

                            size: 45,

                            color: Colors.grey,
                          ),

                          SizedBox(height: 10),

                          Text(
                            'No active emergency requests.',

                            textAlign:
                                TextAlign.center,

                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children:
                        requests.map((doc) {

                      final Map<String, dynamic>
                          data =
                          doc.data()
                              as Map<String,
                                  dynamic>;

                      final String bloodGroup =
                          data['bloodGroup']
                                  ?.toString() ??
                              'Unknown';

                      final String patientName =
                          data['patientName']
                                  ?.toString() ??
                              'Patient';

                      final String hospitalName =
                          data['hospitalName']
                                  ?.toString() ??
                              'Hospital';

                      final String
                          hospitalLocation =
                          data['hospitalLocation']
                                  ?.toString() ??
                              'Location not provided';

                      final String
                          contactNumber =
                          data['contactNumber']
                                  ?.toString() ??
                              'Not provided';

                      final String urgency =
                          data['urgency']
                                  ?.toString() ??
                              'Normal';

                      final String units =
                          data['unitsRequired']
                                  ?.toString() ??
                              '0';

                      final String createdByRole =
                          data['createdByRole']
                                  ?.toString() ??
                              'unknown';

                      final String
                          additionalInformation =
                          data[
                                  'additionalInformation']
                                  ?.toString() ??
                              '';

                      final String donorsContacted =
                          data['donorsContacted']
                                  ?.toString() ??
                              '0';

                      final bool isDonorRequest =
                          createdByRole ==
                              'donor';

                      return Card(
                        margin:
                            const EdgeInsets.only(
                          bottom: 14,
                        ),

                        elevation: 2,

                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),
                        ),

                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),

                          onTap: () {
                            Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                        OrganizationDonorResponsesScreen(
                                  requestId:
                                      doc.id,
                                ),
                              ),
                            );
                          },

                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              18,
                            ),

                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,

                              children: [

                                // ==========================
                                // REQUEST TYPE
                                // ==========================

                                Row(
                                  children: [

                                    Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal:
                                            10,
                                        vertical:
                                            6,
                                      ),

                                      decoration:
                                          BoxDecoration(
                                        color:
                                            isDonorRequest
                                                ? Colors
                                                    .orange
                                                    .shade50
                                                : Colors
                                                    .blue
                                                    .shade50,

                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          20,
                                        ),
                                      ),

                                      child: Text(
                                        isDonorRequest
                                            ? 'DONOR REQUEST'
                                            : 'ORGANIZATION REQUEST',

                                        style:
                                            TextStyle(
                                          color:
                                              isDonorRequest
                                                  ? Colors
                                                      .orange
                                                  : Colors
                                                      .blue,

                                          fontSize:
                                              10,

                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                                    ),

                                    const Spacer(),

                                    Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal:
                                            10,
                                        vertical:
                                            6,
                                      ),

                                      decoration:
                                          BoxDecoration(
                                        color:
                                            Colors
                                                .red
                                                .shade50,

                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          20,
                                        ),
                                      ),

                                      child: Text(
                                        urgency
                                            .toUpperCase(),

                                        style:
                                            const TextStyle(
                                          color:
                                              Colors.red,

                                          fontSize:
                                              11,

                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                // ==========================
                                // BLOOD GROUP
                                // ==========================

                                Text(
                                  '$bloodGroup Blood Required',

                                  style:
                                      const TextStyle(
                                    fontSize: 19,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 10,
                                ),

                                Text(
                                  'Patient: $patientName',

                                  style:
                                      const TextStyle(
                                    fontSize: 14,
                                  ),
                                ),

                                const SizedBox(
                                  height: 5,
                                ),

                                Text(
                                  'Hospital: $hospitalName',

                                  style:
                                      const TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.grey,
                                  ),
                                ),

                                const SizedBox(
                                  height: 5,
                                ),

                                Text(
                                  'Location: $hospitalLocation',

                                  style:
                                      const TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.grey,
                                  ),
                                ),

                                const SizedBox(
                                  height: 5,
                                ),

                                Text(
                                  'Contact: $contactNumber',

                                  style:
                                      const TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.grey,
                                  ),
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                // ==========================
                                // INFORMATION CHIPS
                                // ==========================

                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,

                                  children: [

                                    _organizationInfoChip(
                                      Icons.water_drop,
                                      '$units Unit(s)',
                                    ),

                                    _organizationInfoChip(
                                      Icons.people,
                                      '$donorsContacted Donor(s)',
                                    ),
                                  ],
                                ),

                                // ==========================
                                // ADDITIONAL INFORMATION
                                // ==========================

                                if (additionalInformation
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(
                                    height: 12,
                                  ),

                                  Container(
                                    width:
                                        double.infinity,

                                    padding:
                                        const EdgeInsets
                                            .all(
                                      12,
                                    ),

                                    decoration:
                                        BoxDecoration(
                                      color: Colors
                                          .grey
                                          .shade100,

                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        10,
                                      ),
                                    ),

                                    child: Text(
                                      'Info: '
                                      '$additionalInformation',

                                      style:
                                          const TextStyle(
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(
                                  height: 14,
                                ),

                                // ==========================
                                // VIEW BUTTON
                                // ==========================

                                const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment
                                          .end,

                                  children: [

                                    Text(
                                      'View request',

                                      style:
                                          TextStyle(
                                        color:
                                            Colors.red,

                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),

                                    SizedBox(
                                      width: 5,
                                    ),

                                    Icon(
                                      Icons
                                          .arrow_forward_ios,

                                      color:
                                          Colors.red,

                                      size: 15,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 25),

              // ==================================================
              // INFORMATION
              // ==================================================

              Container(
                width: double.infinity,

                padding:
                    const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.grey.shade100,

                  borderRadius:
                      BorderRadius.circular(15),
                ),

                child: const Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Icon(
                      Icons.info_outline,
                      color: Colors.grey,
                    ),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'Only verified Blood Link organizations '
                        'can access the donor directory and '
                        'manage emergency requests.',

                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // INFORMATION CHIP
  // ============================================================

  Widget _organizationInfoChip(
    IconData icon,
    String text,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),

      decoration: BoxDecoration(
        color: Colors.grey.shade100,

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Row(
        mainAxisSize:
            MainAxisSize.min,

        children: [

          Icon(
            icon,
            size: 16,
            color: Colors.red,
          ),

          const SizedBox(width: 5),

          Text(
            text,

            style: const TextStyle(
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// ORGANIZATION DONOR RESPONSES SCREEN
// ============================================================
// ============================================================
// ORGANIZATION DONOR RESPONSES SCREEN
// ============================================================
class OrganizationDonorResponsesScreen
    extends StatelessWidget {
  final String requestId;

  const OrganizationDonorResponsesScreen({
    super.key,
    required this.requestId,
  });

  // ============================================================
  // CALL DONOR
  // ============================================================

  Future<void> _callDonor(
    BuildContext context,
    String phone,
  ) async {
    final String cleanedPhone = phone.trim();

    if (cleanedPhone.isEmpty) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Donor phone number is not available.',
          ),
        ),
      );

      return;
    }

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: cleanedPhone,
    );

    try {
      final bool launched = await launchUrl(
        phoneUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open phone dialer.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open phone dialer: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // SHARE EMERGENCY REQUEST ON WHATSAPP
  // ============================================================

  Future<void> _shareOnWhatsApp(
    BuildContext context,
    Map<String, dynamic> requestData,
  ) async {
    try {
      const String websiteBaseUrl =
          'https://floral-salad-b086.nazrudeen7200.workers.dev';

      final String emergencyLink =
          '$websiteBaseUrl/emergency/$requestId';

      final String patientName =
          requestData['patientName']?.toString() ??
              'Patient';

      final String bloodGroup =
          requestData['bloodGroup']?.toString() ??
              'Required';

      final String hospitalName =
          requestData['hospitalName']?.toString() ??
              'Hospital';

      final String units =
          requestData['unitsRequired']?.toString() ??
              '1';

      final String urgency =
          requestData['urgency']?.toString() ??
              'Emergency';

      final String hospitalLocation =
          requestData['hospitalLocation']?.toString() ??
              '';

      final String contactNumber =
          requestData['contactNumber']?.toString() ??
              '';

      final String message = '''
🩸 BLOOD LINK – EMERGENCY BLOOD REQUEST

🚨 Urgent blood donation request

👤 Patient: $patientName
🩸 Blood Group: $bloodGroup
💉 Units Required: $units
🏥 Hospital: $hospitalName
📍 Location: $hospitalLocation
📞 Contact: $contactNumber
⚠️ Urgency: $urgency

If you are available and willing to help, please open the Blood Link request:

$emergencyLink

You can view the request and respond directly through Blood Link.

Your help could save a life. ❤️

Blood Link
Donate Blood • Save Lives
''';

      final Uri whatsappUrl = Uri(
        scheme: 'https',
        host: 'wa.me',
        path: '/',
        queryParameters: {
          'text': message,
        },
      );

      final bool launched = await launchUrl(
        whatsappUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open WhatsApp. '
              'Please make sure WhatsApp is installed.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open WhatsApp: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // MARK DONATION COMPLETED
  // ============================================================

  Future<void> _markDonationCompleted(
    BuildContext context,
    QueryDocumentSnapshot<
        Map<String, dynamic>> assignmentDoc,
    Map<String, dynamic> requestData,
  ) async {
    try {
      // ----------------------------------------------------------
      // CURRENT ORGANIZATION
      // ----------------------------------------------------------

      final User? currentUser =
          FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Organization is not logged in.',
            ),
          ),
        );

        return;
      }

      // ----------------------------------------------------------
      // ASSIGNMENT DATA
      // ----------------------------------------------------------

      final Map<String, dynamic> assignmentData =
          assignmentDoc.data();

      final String donorId =
          assignmentData['donorId']?.toString().trim() ??
              assignmentData['assignedDonorId']
                  ?.toString()
                  .trim() ??
              '';

      if (donorId.isEmpty) {
        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Donor ID is missing.',
            ),
          ),
        );

        return;
      }

      // ----------------------------------------------------------
      // CHECK CURRENT RESPONSE STATUS
      // ----------------------------------------------------------

      final String currentResponse =
          assignmentData['response']
                  ?.toString()
                  .toLowerCase()
                  .trim() ??
              'pending';

      if (currentResponse == 'completed') {
        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This donation has already been completed.',
            ),
          ),
        );

        return;
      }

      if (currentResponse != 'accepted') {
        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only an accepted donor can be marked as completed.',
            ),
          ),
        );

        return;
      }

      // ----------------------------------------------------------
      // CONFIRMATION DIALOG
      // ----------------------------------------------------------

      final bool? confirmed =
          await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Confirm Donation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Has this donor actually completed the blood donation?\n\n'
              'Only press "DONATION COMPLETED" after the donation '
              'has been completed.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text(
                  'CANCEL',
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'DONATION COMPLETED',
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      // ----------------------------------------------------------
      // SHOW LOADING
      // ----------------------------------------------------------

      if (!context.mounted) {
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.red,
                    ),
                    SizedBox(height: 15),
                    Text(
                      'Updating donation record...',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // ----------------------------------------------------------
      // LOAD DONOR
      // ----------------------------------------------------------

      final DocumentReference<
          Map<String, dynamic>> donorRef =
          FirebaseFirestore.instance
              .collection('donors')
              .doc(donorId);

      final DocumentSnapshot<
          Map<String, dynamic>> donorSnapshot =
          await donorRef.get();

      if (!donorSnapshot.exists) {
        if (context.mounted) {
          Navigator.pop(context);
        }

        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Donor record was not found.',
            ),
          ),
        );

        return;
      }

      final Map<String, dynamic> donorData =
          donorSnapshot.data() ?? {};

      // ----------------------------------------------------------
      // DONOR INFORMATION
      // ----------------------------------------------------------

      final String donorName =
          donorData['name']?.toString() ??
              assignmentData['donorName']
                  ?.toString() ??
              'Unknown Donor';

      final String donorPhone =
          donorData['phone']?.toString() ??
              assignmentData['donorPhone']
                  ?.toString() ??
              '';

      final String donorBloodGroup =
          donorData['bloodGroup']?.toString() ??
              assignmentData['bloodGroup']
                  ?.toString() ??
              requestData['bloodGroup']
                  ?.toString() ??
              '';

      final String donorLocation =
          donorData['location']?.toString() ??
              assignmentData['location']
                  ?.toString() ??
              '';

      // ----------------------------------------------------------
      // ORGANIZATION INFORMATION
      // ----------------------------------------------------------

      final DocumentSnapshot<
          Map<String, dynamic>> organizationSnapshot =
          await FirebaseFirestore.instance
              .collection('organizations')
              .doc(currentUser.uid)
              .get();

      final Map<String, dynamic> organizationData =
          organizationSnapshot.data() ?? {};

      final String organizationName =
          organizationData['organizationName']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
              ? organizationData['organizationName']
                    .toString()
              : 'Blood Link Organization';

      final String organizationId =
          organizationData['organizationId']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
              ? organizationData['organizationId']
                    .toString()
              : currentUser.uid;

      // ----------------------------------------------------------
      // REQUEST INFORMATION
      // ----------------------------------------------------------

      final String patientName =
          requestData['patientName']?.toString() ??
              'Patient';

      final String bloodGroup =
          requestData['bloodGroup']?.toString() ??
              donorBloodGroup;

      final String hospitalName =
          requestData['hospitalName']?.toString() ??
              'Hospital';

      final String hospitalLocation =
          requestData['hospitalLocation']?.toString() ??
              '';

      final String unitsRequired =
          requestData['unitsRequired']?.toString() ??
              '1';

      // ----------------------------------------------------------
      // DONATION DATE
      // ----------------------------------------------------------

      final Timestamp donationTimestamp =
          Timestamp.now();

      // ----------------------------------------------------------
      // NEW DONATION HISTORY DOCUMENT
      // ----------------------------------------------------------

      final DocumentReference<
          Map<String, dynamic>> historyRef =
          donorRef
              .collection('donationHistory')
              .doc();

      // ----------------------------------------------------------
      // NEW DONATION COUNT
      // ----------------------------------------------------------

      final int currentDonationCount =
          (donorData['donationCount'] is num)
              ? (donorData['donationCount'] as num)
                  .toInt()
              : 0;

      final int newDonationCount =
          currentDonationCount + 1;

      // ----------------------------------------------------------
      // BATCH WRITE
      // ----------------------------------------------------------

      final WriteBatch batch =
          FirebaseFirestore.instance.batch();

      // ==========================================================
      // 1. UPDATE DONOR PROFILE
      // ==========================================================

      batch.update(
        donorRef,
        {
          'lastDonationDate':
              donationTimestamp,
          'donationCount':
              newDonationCount,
          'previousDonationCount':
              currentDonationCount,

          // Donor has just donated.
          // The reminder system can use lastDonationDate
          // to calculate the next eligible reminder date.
          'reminderStatus':
              'ACTIVE',
          'reminderUpdatedAt':
              FieldValue.serverTimestamp(),

          // Donor is temporarily unavailable immediately
          // after donation.
          'availability':
              false,
        },
      );

      // ==========================================================
      // 2. CREATE DONATION HISTORY
      // ==========================================================

      batch.set(
        historyRef,
        {
          'donationDate':
              donationTimestamp,

          'status':
              'completed',

          'verified':
              true,

          'donorId':
              donorId,

          'donorName':
              donorName,

          'donorPhone':
              donorPhone,

          'bloodGroup':
              bloodGroup,

          'donorLocation':
              donorLocation,

          'patientName':
              patientName,

          'hospitalName':
              hospitalName,

          'hospitalLocation':
              hospitalLocation,

          'unitsRequired':
              unitsRequired,

          'requestId':
              requestId,

          'organizationId':
              organizationId,

          'organizationName':
              organizationName,

          'completedBy':
              currentUser.uid,

          'completedAt':
              FieldValue.serverTimestamp(),

          'createdAt':
              FieldValue.serverTimestamp(),
        },
      );

      // ==========================================================
      // 3. UPDATE DONOR ASSIGNMENT
      // ==========================================================

      batch.update(
        assignmentDoc.reference,
        {
          'response':
              'completed',

          'donationStatus':
              'completed',

          'donationCompleted':
              true,

          'donationCompletedAt':
              FieldValue.serverTimestamp(),

          'completedBy':
              currentUser.uid,

          'donorId':
              donorId,

          'donorName':
              donorName,

          'donorPhone':
              donorPhone,

          'bloodGroup':
              bloodGroup,

          'location':
              donorLocation,
        },
      );

      // ==========================================================
      // 4. MARK EMERGENCY REQUEST AS FULFILLED
      // ==========================================================

      final DocumentReference<
          Map<String, dynamic>> requestRef =
          FirebaseFirestore.instance
              .collection('emergencyRequests')
              .doc(requestId);

      batch.update(
        requestRef,
        {
          'status':
              'Fulfilled',

          'fulfilled':
              true,

          'fulfilledBy':
              currentUser.uid,

          'fulfilledDonorId':
              donorId,

          'fulfilledDonorName':
              donorName,

          'fulfilledAt':
              FieldValue.serverTimestamp(),
        },
      );

      // ==========================================================
      // COMMIT EVERYTHING
      // ==========================================================

      await batch.commit();

      // ----------------------------------------------------------
      // CLOSE LOADING
      // ----------------------------------------------------------

      if (context.mounted) {
        Navigator.pop(context);
      }

      // ----------------------------------------------------------
      // SUCCESS MESSAGE
      // ----------------------------------------------------------

      if (!context.mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 55,
            ),
            title: const Text(
              'Donation Completed',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              '$donorName has been recorded as a completed donor.\n\n'
              'Donation count: $newDonationCount\n\n'
              'The NGO donation statistics will update automatically.',
              textAlign: TextAlign.center,
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'OK',
                  ),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      // ----------------------------------------------------------
      // CLOSE LOADING IF OPEN
      // ----------------------------------------------------------

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Unable to complete donation:\n$e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Donor Responses',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('emergencyRequests')
            .doc(requestId)
            .snapshots(),
        builder: (
          context,
          requestSnapshot,
        ) {
          // ------------------------------------------------------
          // LOADING
          // ------------------------------------------------------

          if (requestSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.red,
              ),
            );
          }

          // ------------------------------------------------------
          // ERROR
          // ------------------------------------------------------

          if (requestSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Unable to load emergency request.\n\n'
                  '${requestSnapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          // ------------------------------------------------------
          // REQUEST NOT FOUND
          // ------------------------------------------------------

          if (!requestSnapshot.hasData ||
              !requestSnapshot.data!.exists) {
            return const Center(
              child: Text(
                'Emergency request not found.',
              ),
            );
          }

          final Map<String, dynamic> requestData =
              requestSnapshot.data!.data() ?? {};

          return _buildRequestContent(
            context,
            requestData,
          );
        },
      ),
    );
  }

  // ============================================================
  // REQUEST CONTENT
  // ============================================================

  Widget _buildRequestContent(
    BuildContext context,
    Map<String, dynamic> requestData,
  ) {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('requestDonors')
          .where(
            'requestId',
            isEqualTo: requestId,
          )
          .snapshots(),
      builder: (
        context,
        donorSnapshot,
      ) {
        // --------------------------------------------------------
        // LOADING
        // --------------------------------------------------------

        if (donorSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.red,
            ),
          );
        }

        // --------------------------------------------------------
        // ERROR
        // --------------------------------------------------------

        if (donorSnapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Unable to load donor responses.\n\n'
                '${donorSnapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          );
        }

        final List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>> assignments =
            donorSnapshot.data?.docs ?? [];

        // --------------------------------------------------------
        // REQUEST INFORMATION
        // --------------------------------------------------------

        final String patientName =
            requestData['patientName']?.toString() ??
                'Patient';

        final String bloodGroup =
            requestData['bloodGroup']?.toString() ??
                'Unknown';

        final String hospitalName =
            requestData['hospitalName']?.toString() ??
                'Hospital';

        final String hospitalLocation =
            requestData['hospitalLocation']
                    ?.toString() ??
                'Location';

        final String units =
            requestData['unitsRequired']?.toString() ??
                '0';

        final String urgency =
            requestData['urgency']?.toString() ??
                'Emergency';

        final String contactNumber =
            requestData['contactNumber']?.toString() ??
                '';

        // --------------------------------------------------------
        // ACCEPTED DONORS
        // --------------------------------------------------------

        final List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>> acceptedDonors =
            assignments.where((doc) {
          final Map<String, dynamic> data =
              doc.data();

          return data['response']
                  ?.toString()
                  .toLowerCase()
                  .trim() ==
              'accepted';
        }).toList();

        // --------------------------------------------------------
        // PENDING DONORS
        // --------------------------------------------------------

        final List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>> pendingDonors =
            assignments.where((doc) {
          final Map<String, dynamic> data =
              doc.data();

          return data['response']
                  ?.toString()
                  .toLowerCase()
                  .trim() ==
              'pending';
        }).toList();

        // --------------------------------------------------------
        // DECLINED DONORS
        // --------------------------------------------------------

        final List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>> declinedDonors =
            assignments.where((doc) {
          final Map<String, dynamic> data =
              doc.data();

          return data['response']
                  ?.toString()
                  .toLowerCase()
                  .trim() ==
              'declined';
        }).toList();

        // --------------------------------------------------------
        // COMPLETED DONORS
        // --------------------------------------------------------

        final List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>> completedDonors =
            assignments.where((doc) {
          final Map<String, dynamic> data =
              doc.data();

          return data['response']
                  ?.toString()
                  .toLowerCase()
                  .trim() ==
              'completed';
        }).toList();

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(
              const Duration(
                milliseconds: 500,
              ),
            );
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ==================================================
              // REQUEST HEADER
              // ==================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius:
                      BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.red.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.emergency,
                          color: Colors.red,
                          size: 30,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Emergency Blood Request',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    _requestInfoRow(
                      Icons.person,
                      'Patient',
                      patientName,
                    ),

                    _requestInfoRow(
                      Icons.bloodtype,
                      'Blood Group',
                      bloodGroup,
                    ),

                    _requestInfoRow(
                      Icons.water_drop,
                      'Units',
                      units,
                    ),

                    _requestInfoRow(
                      Icons.local_hospital,
                      'Hospital',
                      hospitalName,
                    ),

                    _requestInfoRow(
                      Icons.location_on,
                      'Location',
                      hospitalLocation,
                    ),

                    _requestInfoRow(
                      Icons.priority_high,
                      'Urgency',
                      urgency,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ==================================================
              // WHATSAPP SHARE
              // ==================================================

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _shareOnWhatsApp(
                      context,
                      requestData,
                    );
                  },
                  icon: const Icon(
                    Icons.share,
                  ),
                  label: const Text(
                    'SHARE ON WHATSAPP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.green,
                    foregroundColor:
                        Colors.white,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // ==================================================
              // COMPLETED DONORS
              // ==================================================

              if (completedDonors.isNotEmpty) ...[
                _sectionTitle(
                  'DONATION COMPLETED',
                  Icons.check_circle,
                  Colors.green,
                  completedDonors.length,
                ),

                const SizedBox(height: 10),

                ...completedDonors.map(
                  (doc) {
                    return _buildDonorCard(
                      context,
                      doc,
                      requestData,
                      showCallButton: false,
                      showCompletedButton: false,
                    );
                  },
                ),

                const SizedBox(height: 20),
              ],

              // ==================================================
              // ACCEPTED DONORS
              // ==================================================

              _sectionTitle(
                'DONORS WILLING TO HELP',
                Icons.volunteer_activism,
                Colors.green,
                acceptedDonors.length,
              ),

              const SizedBox(height: 10),

              if (acceptedDonors.isEmpty)
                _emptyResponseCard(
                  'No donor has accepted yet.',
                  Icons.people_outline,
                ),

              ...acceptedDonors.map(
                (doc) {
                  return _buildDonorCard(
                    context,
                    doc,
                    requestData,
                    showCallButton: true,
                    showCompletedButton: true,
                  );
                },
              ),

              const SizedBox(height: 20),

              // ==================================================
              // PENDING DONORS
              // ==================================================

              _sectionTitle(
                'WAITING FOR RESPONSE',
                Icons.hourglass_empty,
                Colors.orange,
                pendingDonors.length,
              ),

              const SizedBox(height: 10),

              if (pendingDonors.isEmpty)
                _emptyResponseCard(
                  'No pending donor responses.',
                  Icons.hourglass_disabled,
                ),

              ...pendingDonors.map(
                (doc) {
                  return _buildDonorCard(
                    context,
                    doc,
                    requestData,
                    showCallButton: false,
                    showCompletedButton: false,
                  );
                },
              ),

              const SizedBox(height: 20),

              // ==================================================
              // DECLINED DONORS
              // ==================================================

              _sectionTitle(
                'DECLINED',
                Icons.close,
                Colors.grey,
                declinedDonors.length,
              ),

              const SizedBox(height: 10),

              if (declinedDonors.isEmpty)
                _emptyResponseCard(
                  'No declined responses.',
                  Icons.person_off,
                ),

              ...declinedDonors.map(
                (doc) {
                  return _buildDonorCard(
                    context,
                    doc,
                    requestData,
                    showCallButton: false,
                    showCompletedButton: false,
                  );
                },
              ),

              const SizedBox(height: 25),

              // ==================================================
              // CONTACT NUMBER
              // ==================================================

              if (contactNumber.trim().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Emergency Contact',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              contactNumber,
                              style:
                                  const TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _callDonor(
                            context,
                            contactNumber,
                          );
                        },
                        icon: const Icon(
                          Icons.call,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 25),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // DONOR CARD
  // ============================================================

  Widget _buildDonorCard(
    BuildContext context,
    QueryDocumentSnapshot<
        Map<String, dynamic>> doc,
    Map<String, dynamic> requestData, {
    required bool showCallButton,
    required bool showCompletedButton,
  }) {
    final Map<String, dynamic> donorData =
        doc.data();

    final String donorName =
        donorData['donorName']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? donorData['donorName'].toString()
            : donorData['name']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? donorData['name'].toString()
                : 'Unknown Donor';

    final String donorPhone =
        donorData['donorPhone']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? donorData['donorPhone'].toString()
            : donorData['phone']
                    ?.toString() ??
                '';

    final String donorBloodGroup =
        donorData['bloodGroup']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? donorData['bloodGroup'].toString()
            : 'Unknown';

    final String donorLocation =
        donorData['location']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? donorData['location'].toString()
            : 'Location not available';

    final String response =
        donorData['response']
                ?.toString()
                .toLowerCase()
                .trim() ??
            'pending';

    final bool accepted =
        response == 'accepted';

    final bool completed =
        response == 'completed';

    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: completed
              ? Colors.green.shade300
              : accepted
                  ? Colors.green.shade200
                  : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.grey.withValues(
              alpha: 0.10,
            ),
            blurRadius: 7,
            offset:
                const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // ======================================================
          // DONOR NAME
          // ======================================================

          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor:
                    completed
                        ? Colors.green.shade50
                        : accepted
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                child: Icon(
                  completed
                      ? Icons.check
                      : Icons.person,
                  color:
                      completed
                          ? Colors.green
                          : accepted
                              ? Colors.green
                              : Colors.red,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      donorName,
                      style:
                          const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completed
                          ? 'DONATION COMPLETED'
                          : response
                              .toUpperCase(),
                      style: TextStyle(
                        color: completed
                            ? Colors.green
                            : accepted
                                ? Colors.green
                                : Colors.grey,
                        fontSize: 12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.red.shade50,
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  donorBloodGroup,
                  style:
                      const TextStyle(
                    color: Colors.red,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ======================================================
          // LOCATION
          // ======================================================

          _donorInfoRow(
            Icons.location_on,
            donorLocation,
          ),

          // ======================================================
          // PHONE
          // ======================================================

          if (donorPhone.trim().isNotEmpty)
            _donorInfoRow(
              Icons.phone,
              donorPhone,
            ),

          // ======================================================
          // CALL BUTTON
          // ======================================================

          if (showCallButton &&
              donorPhone.trim().isNotEmpty) ...[
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child:
                  ElevatedButton.icon(
                onPressed: () {
                  _callDonor(
                    context,
                    donorPhone,
                  );
                },
                icon: const Icon(
                  Icons.call,
                ),
                label: const Text(
                  'CALL DONOR',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.green,
                  foregroundColor:
                      Colors.white,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ======================================================
          // DONATION COMPLETED BUTTON
          // ======================================================

          if (showCompletedButton &&
              accepted) ...[
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 50,
              child:
                  ElevatedButton.icon(
                onPressed: () {
                  _markDonationCompleted(
                    context,
                    doc,
                    requestData,
                  );
                },
                icon: const Icon(
                  Icons.check_circle,
                ),
                label: const Text(
                  'DONATION COMPLETED',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.red,
                  foregroundColor:
                      Colors.white,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ======================================================
          // COMPLETED INFORMATION
          // ======================================================

          if (completed) ...[
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    Colors.green.shade50,
                borderRadius:
                    BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified,
                    color: Colors.green,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Donation recorded successfully.',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // REQUEST INFO ROW
  // ============================================================

  Widget _requestInfoRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.red,
          ),
          const SizedBox(width: 10),
          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DONOR INFO ROW
  // ============================================================

  Widget _donorInfoRow(
    IconData icon,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle(
    String title,
    IconData icon,
    Color color,
    int count,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight:
                  FontWeight.bold,
              color: color,
            ),
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration:
              BoxDecoration(
            color:
                color.withValues(
              alpha: 0.10,
            ),
            borderRadius:
                BorderRadius.circular(
              20,
            ),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY RESPONSE CARD
  // ============================================================

  Widget _emptyResponseCard(
    String message,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style:
                  const TextStyle(
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// EMERGENCY BLOOD REQUEST SCREEN
// ============================================================

class EmergencyRequestScreen extends StatefulWidget {
  const EmergencyRequestScreen({super.key});

  @override
  State<EmergencyRequestScreen> createState() =>
      _EmergencyRequestScreenState();
}

class _EmergencyRequestScreenState
    extends State<EmergencyRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController patientController =
      TextEditingController();

  final TextEditingController unitsController =
      TextEditingController();

  final TextEditingController hospitalController =
      TextEditingController();

  final TextEditingController locationController =
      TextEditingController();

  bool isSubmitting = false;

  String selectedBloodGroup = 'A+';
  String selectedUrgency = 'Critical';

  final List<String> bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final List<String> urgencyLevels = [
    'Critical',
    'Urgent',
    'Normal',
  ];

  @override
  void dispose() {
    patientController.dispose();
    unitsController.dispose();
    hospitalController.dispose();
    locationController.dispose();
    super.dispose();
  }

  // ============================================================
  // SUBMIT EMERGENCY REQUEST
  // ============================================================

  Future<void> submitEmergencyRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please login again to continue.',
          ),
        ),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final units = int.parse(
        unitsController.text.trim(),
      );

      // ========================================================
      // STEP 1: CREATE EMERGENCY REQUEST
      // ========================================================

      final requestRef = await FirebaseFirestore.instance
          .collection('emergencyRequests')
          .add({
        'patientName': patientController.text.trim(),
        'bloodGroup': selectedBloodGroup,
        'unitsRequired': units,
        'hospitalName': hospitalController.text.trim(),
        'hospitalLocation': locationController.text.trim(),
        'urgency': selectedUrgency,

        // ------------------------------------------------------
        // CREATOR INFORMATION
        // ------------------------------------------------------

        'createdBy': user.uid,
        'createdByEmail': user.email ?? '',

        // IMPORTANT:
        // This identifies the request as an organization request.
        'createdByRole': 'organization',

        // ------------------------------------------------------
        // REQUEST INFORMATION
        // ------------------------------------------------------

        'createdAt': FieldValue.serverTimestamp(),
        'status': 'Searching',

        // ------------------------------------------------------
        // DONOR TRACKING
        // ------------------------------------------------------

        'donorsContacted': 0,
        'donorsAccepted': 0,
        'donorsDeclined': 0,

        // ------------------------------------------------------
        // DONATION TRACKING
        // ------------------------------------------------------

        'donationsCompleted': 0,
        'unitsDonated': 0,
      });

      final requestId = requestRef.id;

      debugPrint(
        'Emergency Request ID: $requestId',
      );

      // ========================================================
      // STEP 2: FIND MATCHING AVAILABLE DONORS
      // ========================================================

      final donorsSnapshot = await FirebaseFirestore.instance
          .collection('donors')
          .where(
            'bloodGroup',
            isEqualTo: selectedBloodGroup,
          )
          .where(
            'availability',
            isEqualTo: true,
          )
          .get();

      debugPrint(
        'Matching donors found: '
        '${donorsSnapshot.docs.length}',
      );

      // ========================================================
      // STEP 3: CREATE DONOR ASSIGNMENTS
      // ========================================================

      int donorsAssigned = 0;

      for (final donorDoc in donorsSnapshot.docs) {
        final donorData = donorDoc.data();

        await FirebaseFirestore.instance
            .collection('requestDonors')
            .add({
          // ----------------------------------------------------
          // REQUEST INFORMATION
          // ----------------------------------------------------

          'requestId': requestId,

          // ----------------------------------------------------
          // DONOR INFORMATION
          // ----------------------------------------------------

          'donorId': donorDoc.id,
          'donorName': donorData['name'] ?? '',
          'donorEmail': donorData['email'] ?? '',
          'donorPhone': donorData['phone'] ?? '',
          'bloodGroup': donorData['bloodGroup'] ?? '',
          'location': donorData['location'] ?? '',

          // ----------------------------------------------------
          // RESPONSE STATUS
          // ----------------------------------------------------

          'response': 'pending',

          // ----------------------------------------------------
          // ASSIGNMENT INFORMATION
          // ----------------------------------------------------

          'assignedAt': FieldValue.serverTimestamp(),

          // ----------------------------------------------------
          // EMERGENCY INFORMATION
          // ----------------------------------------------------

          'patientName':
              patientController.text.trim(),

          'hospitalName':
              hospitalController.text.trim(),

          'hospitalLocation':
              locationController.text.trim(),

          'unitsRequired': units,

          'urgency': selectedUrgency,
        });

        donorsAssigned++;

        debugPrint(
          'Donor assigned: ${donorDoc.id}',
        );
      }

      // ========================================================
      // STEP 4: UPDATE EMERGENCY REQUEST
      // ========================================================

      await FirebaseFirestore.instance
          .collection('emergencyRequests')
          .doc(requestId)
          .update({
        'donorsContacted': donorsAssigned,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        isSubmitting = false;
      });

      // ========================================================
      // STEP 5: SHOW SUCCESS MESSAGE
      // ========================================================

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Request Created',
            ),
            content: Text(
              'The emergency blood request has been '
              'saved successfully.\n\n'
              'Matching donors found: $donorsAssigned\n\n'
              'The request has been added to the '
              'matching donor list.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create request: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // TEXT FIELD
  // ============================================================

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Blood Request',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Raise Emergency Request',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Enter the patient and blood requirement '
                  'details below.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 24),

                // ------------------------------------------------
                // PATIENT NAME
                // ------------------------------------------------

                buildTextField(
                  controller: patientController,
                  label: 'Patient Name',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Please enter patient name';
                    }

                    return null;
                  },
                ),

                // ------------------------------------------------
                // BLOOD GROUP
                // ------------------------------------------------

                DropdownButtonFormField<String>(
                  initialValue: selectedBloodGroup,
                  decoration: InputDecoration(
                    labelText: 'Required Blood Group',
                    prefixIcon: const Icon(
                      Icons.bloodtype,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                  items: bloodGroups.map((group) {
                    return DropdownMenuItem<String>(
                      value: group,
                      child: Text(group),
                    );
                  }).toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            selectedBloodGroup = value;
                          });
                        },
                ),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // UNITS
                // ------------------------------------------------

                buildTextField(
                  controller: unitsController,
                  label: 'Units Required',
                  icon: Icons.water_drop,
                  keyboardType:
                      TextInputType.number,
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Please enter units required';
                    }

                    final units =
                        int.tryParse(value.trim());

                    if (units == null ||
                        units <= 0) {
                      return 'Enter a valid number';
                    }

                    return null;
                  },
                ),

                // ------------------------------------------------
                // HOSPITAL
                // ------------------------------------------------

                buildTextField(
                  controller: hospitalController,
                  label: 'Hospital Name',
                  icon: Icons.local_hospital,
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Please enter hospital name';
                    }

                    return null;
                  },
                ),

                // ------------------------------------------------
                // HOSPITAL LOCATION
                // ------------------------------------------------

                buildTextField(
                  controller: locationController,
                  label: 'Hospital Location',
                  icon: Icons.location_on,
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Please enter hospital location';
                    }

                    return null;
                  },
                ),

                // ------------------------------------------------
                // URGENCY
                // ------------------------------------------------

                DropdownButtonFormField<String>(
                  initialValue: selectedUrgency,
                  decoration: InputDecoration(
                    labelText: 'Urgency',
                    prefixIcon: const Icon(
                      Icons.warning,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                  items: urgencyLevels.map((urgency) {
                    return DropdownMenuItem<String>(
                      value: urgency,
                      child: Text(urgency),
                    );
                  }).toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            selectedUrgency = value;
                          });
                        },
                ),

                const SizedBox(height: 28),

                // ------------------------------------------------
                // SUBMIT BUTTON
                // ------------------------------------------------

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : submitEmergencyRequest,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send,
                          ),
                    label: Text(
                      isSubmitting
                          ? 'Creating Request...'
                          : 'Raise Emergency Request',
                    ),
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ------------------------------------------------
                // INFORMATION
                // ------------------------------------------------

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius:
                        BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.shade100,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red,
                      ),

                      SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          'Blood Link will search the donor '
                          'directory for available donors '
                          'with the required blood group.',
                          style: TextStyle(
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ACTIVE REQUESTS SCREEN
// ============================================================

class ActiveRequestsScreen extends StatelessWidget {
  const ActiveRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Requests'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.bloodtype,
                    color: Colors.red,
                    size: 55,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A+ BLOOD REQUIRED',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CRITICAL',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _requestInfo(
              Icons.local_hospital,
              'Hospital',
              'ABC Hospital',
            ),

            _requestInfo(
              Icons.location_on,
              'Location',
              'Chennai',
            ),

            _requestInfo(
              Icons.water_drop,
              'Blood Requirement',
              'A+ • 2 Units',
            ),

            _requestInfo(
              Icons.search,
              'Status',
              'Searching for suitable donors',
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.psychology,
                    color: Colors.red,
                    size: 40,
                  ),

                  SizedBox(height: 10),

                  Text(
                    'Blood Link Priority Matching',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    'The system can prioritize suitable donors '
                    'based on blood-group compatibility, location, '
                    'donation history, availability and response history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    'Actual medical eligibility must be confirmed '
                    'by an authorized medical professional or blood bank.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestInfo(
    IconData icon,
    String title,
    String value,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.red.shade50,
            child: Icon(
              icon,
              color: Colors.red,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// BLOOD LINK MATCHING INFORMATION SCREEN
// ============================================================

class MatchingInfoScreen extends StatelessWidget {
  const MatchingInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blood Link Matching'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.psychology,
                    color: Colors.red,
                    size: 60,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Smart Donor Matching',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Blood Link prioritizes suitable donors '
                    'without exposing a public donor list.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Matching Factors',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            _matchingFactor(
              Icons.bloodtype,
              'Blood Group',
              'Checks compatible blood-group information.',
            ),

            _matchingFactor(
              Icons.location_on,
              'Location',
              'Considers the donor location and emergency location.',
            ),

            _matchingFactor(
              Icons.history,
              'Donation History',
              'Uses recorded donation history when prioritizing donors.',
            ),

            _matchingFactor(
              Icons.event_available,
              'Availability',
              'Considers whether the donor is available to respond.',
            ),

            _matchingFactor(
              Icons.reply,
              'Response History',
              'Can consider previous responses to emergency requests.',
            ),

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.security,
                    color: Colors.grey,
                    size: 35,
                  ),

                  SizedBox(height: 10),

                  Text(
                    'Privacy First',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    'Donor contact information is not displayed '
                    'as a public list. Blood Link handles the '
                    'matching process privately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.medical_services,
                    color: Colors.orange,
                  ),

                  SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      'Blood Link can assist with prioritization, '
                      'but actual medical eligibility and donation '
                      'decisions must be confirmed by an authorized '
                      'medical professional or blood bank.',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchingFactor(
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.red.shade50,
            child: Icon(
              icon,
              color: Colors.red,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// NEED BLOOD SCREEN
// ============================================================

class NeedBloodScreen extends StatefulWidget {
  const NeedBloodScreen({super.key});

  @override
  State<NeedBloodScreen> createState() => _NeedBloodScreenState();
}

class _NeedBloodScreenState extends State<NeedBloodScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController patientController = TextEditingController();
  final TextEditingController unitsController = TextEditingController();
  final TextEditingController hospitalController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController contactController = TextEditingController();
  final TextEditingController detailsController = TextEditingController();

  String selectedBloodGroup = 'A+';
  String selectedUrgency = 'Critical';

  bool isSubmitting = false;

  final List<String> bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final List<String> urgencyLevels = [
    'Critical',
    'Urgent',
    'Normal',
  ];

  @override
  void dispose() {
    patientController.dispose();
    unitsController.dispose();
    hospitalController.dispose();
    locationController.dispose();
    contactController.dispose();
    detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitEmergencyRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please login before raising a blood request.',
          ),
        ),
      );
      return;
    }

    final int? units = int.tryParse(
      unitsController.text.trim(),
    );

    if (units == null || units <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid number of units.',
          ),
        ),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final requestRef = FirebaseFirestore.instance
          .collection('emergencyRequests')
          .doc();

      await requestRef.set({
        'patientName': patientController.text.trim(),
        'bloodGroup': selectedBloodGroup,
        'unitsRequired': units,
        'hospitalName': hospitalController.text.trim(),
        'hospitalLocation': locationController.text.trim(),
        'contactNumber': contactController.text.trim(),
        'urgency': selectedUrgency,
        'additionalInformation': detailsController.text.trim(),

        // Request creator
        'createdBy': user.uid,
        'createdByEmail': user.email ?? '',
        'createdByRole': 'donor',

        // Request status
        'status': 'Searching',

        // Counters
        'donorsContacted': 0,
        'donorsAccepted': 0,
        'donorsDeclined': 0,
        'donationsCompleted': 0,
        'unitsDonated': 0,

        // Timestamp
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Request Submitted',
            ),
            content: const Text(
              'Your blood request has been submitted successfully. '
              'Verified NGOs and hospitals can now see your request.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to submit request: $e',
          ),
        ),
      );
    }
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Need Blood?'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Raise Emergency Blood Request',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Enter the patient and hospital details. '
                  'Verified organizations can review your request.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                // Patient Name
                TextFormField(
                  controller: patientController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Patient Name',
                    Icons.person,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter patient name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Blood Group
                DropdownButtonFormField<String>(
                  initialValue: selectedBloodGroup,
                  decoration: _inputDecoration(
                    'Required Blood Group',
                    Icons.bloodtype,
                  ),
                  items: bloodGroups.map((group) {
                    return DropdownMenuItem<String>(
                      value: group,
                      child: Text(group),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedBloodGroup = value;
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Units Required
                TextFormField(
                  controller: unitsController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Units Required',
                    Icons.local_hospital,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter number of units';
                    }

                    final units = int.tryParse(
                      value.trim(),
                    );

                    if (units == null || units <= 0) {
                      return 'Enter a valid number';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Hospital Name
                TextFormField(
                  controller: hospitalController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Hospital Name',
                    Icons.local_hospital_outlined,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter hospital name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Hospital Location
                TextFormField(
                  controller: locationController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Hospital Location',
                    Icons.location_on,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter hospital location';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Contact Number
                TextFormField(
                  controller: contactController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Contact Number',
                    Icons.phone,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter contact number';
                    }

                    if (value.trim().length < 10) {
                      return 'Enter a valid contact number';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Urgency
                DropdownButtonFormField<String>(
                  initialValue: selectedUrgency,
                  decoration: _inputDecoration(
                    'Urgency',
                    Icons.priority_high,
                  ),
                  items: urgencyLevels.map((urgency) {
                    return DropdownMenuItem<String>(
                      value: urgency,
                      child: Text(urgency),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedUrgency = value;
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Additional Information
                TextFormField(
                  controller: detailsController,
                  maxLines: 4,
                  decoration: _inputDecoration(
                    'Additional Information',
                    Icons.info_outline,
                  ),
                ),

                const SizedBox(height: 20),

                // Privacy Information
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.blue.withValues(
                      alpha: 0.08,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.security,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your request will be shared with verified '
                          'NGOs/Hospitals through Blood Link so they can '
                          'review and coordinate assistance.',
                          style: TextStyle(
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : _submitEmergencyRequest,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      isSubmitting
                          ? 'Submitting...'
                          : 'RAISE BLOOD REQUEST',
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class AboutBloodLinkScreen extends StatelessWidget {
  const AboutBloodLinkScreen({super.key});

  Future<void> _openEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'nazrudeen7200@gmail.com',
      queryParameters: {
        'subject': 'Blood Link App',
      },
    );

    try {
      final bool opened = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        debugPrint('Could not open email app.');
      }
    } catch (e) {
      debugPrint('Email error: $e');
    }
  }

  Future<void> _openGitHub() async {
    final Uri githubUri = Uri.parse(
      'https://github.com/nazru7200',
    );

    try {
      final bool opened = await launchUrl(
        githubUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        debugPrint('Could not open GitHub.');
      }
    } catch (e) {
      debugPrint('GitHub error: $e');
    }
  }

  Future<void> _openLinkedIn() async {
    final Uri linkedInUri = Uri.parse(
      'https://www.linkedin.com/in/nazrudeen-72008-9255ph/',
    );

    try {
      final bool opened = await launchUrl(
        linkedInUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        debugPrint('Could not open LinkedIn.');
      }
    } catch (e) {
      debugPrint('LinkedIn error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Blood Link'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // BLOOD LINK LOGO
            Image.asset(
              'assets/logo.png',
              width: 170,
              height: 170,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 15),

            const Text(
              'About Blood Link',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Connecting blood donors with people in need',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 25),

            // ABOUT THE APP
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'About the App',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Blood Link is an AI-powered blood donation and emergency '
              'blood management application designed to connect blood '
              'donors with verified hospitals and NGOs during emergency '
              'situations. The platform helps manage donor information, '
              'donation history, availability, emergency blood requests, '
              'and smart donor matching.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 25),

            // KEY FEATURES
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Key Features',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            _featureItem(
              Icons.person_add,
              'Donor Registration',
            ),

            _featureItem(
              Icons.emergency,
              'Emergency Blood Requests',
            ),

            _featureItem(
              Icons.notifications_active,
              'Emergency Donor Alerts',
            ),

            _featureItem(
              Icons.calendar_month,
              'Donation History & Reminders',
            ),

            _featureItem(
              Icons.local_hospital,
              'Verified NGO / Hospital Access',
            ),

            _featureItem(
              Icons.people,
              'Donor Directory',
            ),

            _featureItem(
              Icons.search,
              'Blood Group & Location Search',
            ),

            _featureItem(
              Icons.event_available,
              'Donation Status & Availability',
            ),

            _featureItem(
              Icons.table_chart,
              'Excel Donor Data Export',
            ),

            _featureItem(
              Icons.psychology,
              'Smart Donor Matching',
            ),

            const SizedBox(height: 30),

            const Divider(),

            const SizedBox(height: 20),

            // DEVELOPER
            const Text(
              'About Developer',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            const CircleAvatar(
              radius: 38,
              child: Icon(
                Icons.person,
                size: 42,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'A. Nazru Deen',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // EMAIL
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.email,
                  color: Colors.red,
                ),
                title: const Text(
                  'Email',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'nazrudeen7200@gmail.com',
                ),
                trailing: const Icon(
                  Icons.open_in_new,
                ),
                onTap: _openEmail,
              ),
            ),

            // GITHUB
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.code,
                  color: Colors.red,
                ),
                title: const Text(
                  'GitHub',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'github.com/nazru7200',
                ),
                trailing: const Icon(
                  Icons.open_in_new,
                ),
                onTap: _openGitHub,
              ),
            ),

            // LINKEDIN
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.work,
                  color: Colors.red,
                ),
                title: const Text(
                  'LinkedIn',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'A. Nazru Deen',
                ),
                trailing: const Icon(
                  Icons.open_in_new,
                ),
                onTap: _openLinkedIn,
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              'Blood Link',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Donate Blood. Save Lives.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }

  static Widget _featureItem(
    IconData icon,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.red,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// DONOR DIRECTORY SCREEN
// ============================================================

class DonorDirectoryScreen extends StatefulWidget {
  const DonorDirectoryScreen({super.key});

  @override
  State<DonorDirectoryScreen> createState() =>
      _DonorDirectoryScreenState();
}

class _DonorDirectoryScreenState
    extends State<DonorDirectoryScreen> {
  // ------------------------------------------------------------
  // SETTINGS
  // ------------------------------------------------------------

  bool isLoading = true;

  List<Map<String, dynamic>> donors = [];

  String selectedBloodGroup = 'All';

  String selectedVerification = 'All';

  final TextEditingController searchController =
      TextEditingController();

  // ------------------------------------------------------------
  // BLOOD GROUPS
  // ------------------------------------------------------------

  final List<String> bloodGroups = [
    'All',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  // ------------------------------------------------------------
  // VERIFICATION FILTER
  // ------------------------------------------------------------

  final List<String> verificationFilters = [
    'All',
    'Verified',
    'Unverified',
  ];

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadDonors();

    searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    searchController.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------
  // LOAD DONORS
  // ------------------------------------------------------------

  Future<void> _loadDonors() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      final QuerySnapshot<Map<String, dynamic>>
          snapshot =
          await FirebaseFirestore.instance
              .collection('donors')
              .get();

      final List<Map<String, dynamic>> loadedDonors =
          snapshot.docs.map((doc) {
        final Map<String, dynamic> data =
            doc.data();

        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        donors = loadedDonors;
        isLoading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to load donors: '
            '${e.message ?? 'Permission denied.'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      debugPrint(
        'Donor directory error: $e',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong while loading donors.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // MANUAL DONOR VERIFICATION
  // ------------------------------------------------------------

  Future<void> _verifyDonor(
    Map<String, dynamic> donor,
  ) async {
    final String donorId =
        donor['id']?.toString() ?? '';

    final String donorName =
        donor['name']?.toString() ??
        'this donor';

    if (donorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Donor ID not found.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // CONFIRMATION DIALOG
    // ----------------------------------------------------------

    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Verify Donor',
          ),
          content: Text(
            'Are you sure you want to manually '
            'verify $donorName as a Blood Link donor?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'CANCEL',
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'VERIFY',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final User? organizationUser =
          FirebaseAuth.instance.currentUser;

      if (organizationUser == null) {
        throw Exception(
          'Organization is not logged in.',
        );
      }

      // --------------------------------------------------------
      // UPDATE DONOR VERIFICATION
      // --------------------------------------------------------

      await FirebaseFirestore.instance
          .collection('donors')
          .doc(donorId)
          .update({
        'donorVerified': true,
        'donorVerificationStatus': 'Verified',
        'verifiedAt':
            FieldValue.serverTimestamp(),
        'verifiedBy':
            organizationUser.uid,
      });

      // --------------------------------------------------------
      // UPDATE LOCAL LIST
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        final int index = donors.indexWhere(
          (item) => item['id'] == donorId,
        );

        if (index != -1) {
          donors[index]['donorVerified'] =
              true;

          donors[index]
                  ['donorVerificationStatus'] =
              'Verified';
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$donorName has been manually verified.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification failed: '
            '${e.message ?? 'Permission denied.'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      debugPrint(
        'Donor verification error: $e',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify donor.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // FORMAT DATE
  // ------------------------------------------------------------

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'Not available';
    }

    if (value is Timestamp) {
      final DateTime date = value.toDate();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}/'
          '${value.year}';
    }

    if (value is String &&
        value.isNotEmpty) {
      return value;
    }

    return 'Not available';
  }

  // ------------------------------------------------------------
  // FILTER DONORS
  // ------------------------------------------------------------

  List<Map<String, dynamic>> get filteredDonors {
    final String searchText =
        searchController.text.trim().toLowerCase();

    return donors.where((donor) {
      final String bloodGroup =
          donor['bloodGroup']?.toString() ?? '';

      final bool bloodGroupMatches =
          selectedBloodGroup == 'All' ||
          bloodGroup == selectedBloodGroup;

      final bool donorVerified =
          donor['donorVerified'] == true;

      final bool verificationMatches =
          selectedVerification == 'All' ||
          (selectedVerification == 'Verified' &&
              donorVerified) ||
          (selectedVerification == 'Unverified' &&
              !donorVerified);

      final String name =
          donor['name']
                  ?.toString()
                  .toLowerCase() ??
              '';

      final String location =
          donor['location']
                  ?.toString()
                  .toLowerCase() ??
              '';

      final String phone =
          donor['phone']
                  ?.toString()
                  .toLowerCase() ??
              '';

      final bool searchMatches =
          searchText.isEmpty ||
          name.contains(searchText) ||
          location.contains(searchText) ||
          phone.contains(searchText);

      return bloodGroupMatches &&
          verificationMatches &&
          searchMatches;
    }).toList();
  }

  // ------------------------------------------------------------
  // DONOR CARD
  // ------------------------------------------------------------

  Widget _donorCard(
    Map<String, dynamic> donor,
  ) {
    final String name =
        donor['name']?.toString() ??
            'Unknown Donor';

    final String bloodGroup =
        donor['bloodGroup']?.toString() ??
            'Unknown';

    final String location =
        donor['location']?.toString() ??
            'Not available';

    final String phone =
        donor['phone']?.toString() ??
            'Not available';

    final String lastDonation =
        _formatDate(
      donor['lastDonationDate'],
    );

    final int donationCount =
        donor['donationCount'] is num
            ? (donor['donationCount'] as num)
                .toInt()
            : 0;

    final bool availability =
        donor['availability'] == true;

    final bool donorVerified =
        donor['donorVerified'] == true;

    final String verificationStatus =
        donorVerified
            ? 'Verified'
            : 'Unverified';

    return Card(
      margin:
          const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            // --------------------------------------------------
            // NAME + BLOOD GROUP
            // --------------------------------------------------

            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor:
                      Colors.red.shade50,
                  child: const Icon(
                    Icons.person,
                    color: Colors.red,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style:
                            const TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Row(
                        children: [
                          const Icon(
                            Icons.bloodtype,
                            color: Colors.red,
                            size: 18,
                          ),
                          const SizedBox(
                            width: 5,
                          ),
                          Text(
                            bloodGroup,
                            style:
                                const TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ------------------------------------------------
                // AVAILABILITY
                // ------------------------------------------------

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration:
                      BoxDecoration(
                    color: availability
                        ? Colors.green.shade50
                        : Colors.grey.shade200,
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    availability
                        ? 'Available'
                        : 'Unavailable',
                    style: TextStyle(
                      color: availability
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            const Divider(),

            const SizedBox(height: 8),

            // --------------------------------------------------
            // LOCATION
            // --------------------------------------------------

            _infoRow(
              Icons.location_on,
              'Location',
              location,
            ),

            // --------------------------------------------------
            // CONTACT
            // --------------------------------------------------

            _infoRow(
              Icons.phone,
              'Contact',
              phone,
            ),

            // --------------------------------------------------
            // LAST DONATION
            // --------------------------------------------------

            _infoRow(
              Icons.calendar_month,
              'Last Donation',
              lastDonation,
            ),

            // --------------------------------------------------
            // DONATION COUNT
            // --------------------------------------------------

            _infoRow(
              Icons.volunteer_activism,
              'Donation Count',
              '$donationCount donation${donationCount == 1 ? '' : 's'}',
            ),

            const SizedBox(height: 5),

            // --------------------------------------------------
            // MANUAL VERIFICATION
            // --------------------------------------------------

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: donorVerified
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        donorVerified
                            ? Icons.verified
                            : Icons
                                .pending_actions,
                        color: donorVerified
                            ? Colors.green
                            : Colors.orange,
                        size: 21,
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: Text(
                          'Donor Verification: '
                          '$verificationStatus',
                          style: TextStyle(
                            color: donorVerified
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (!donorVerified) ...[
                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _verifyDonor(
                          donor,
                        ),
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.red,
                          foregroundColor:
                              Colors.white,
                        ),
                        icon: const Icon(
                          Icons.verified,
                        ),
                        label: const Text(
                          'VERIFY DONOR',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // INFORMATION ROW
  // ------------------------------------------------------------

  Widget _infoRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.red,
          ),

          const SizedBox(width: 10),

          SizedBox(
            width: 105,
            child: Text(
              title,
              style: TextStyle(
                color:
                    Colors.grey.shade700,
                fontSize: 14,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          Expanded(
            child: SelectableText(
              value,
              style:
                  const TextStyle(
                fontSize: 14,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // EMPTY STATE
  // ------------------------------------------------------------

  Widget _emptyDonors() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 70,
              color: Colors.grey.shade400,
            ),

            const SizedBox(height: 15),

            const Text(
              'No Donors Found',
              style: TextStyle(
                fontSize: 21,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'No donors match the selected filters.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>>
        visibleDonors =
        filteredDonors;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Donor Directory',
        ),
        actions: [
          IconButton(
            onPressed:
                isLoading
                    ? null
                    : _loadDonors,
            icon: const Icon(
              Icons.refresh,
            ),
            tooltip: 'Refresh',
          ),
        ],
      ),

      body: Column(
        children: [
          // ----------------------------------------------------
          // HEADER
          // ----------------------------------------------------

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(18),
            color: Colors.red.shade50,
            child: Row(
              children: [
                const Icon(
                  Icons.people,
                  color: Colors.red,
                  size: 30,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registered Donors',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        '${visibleDonors.length} donor${visibleDonors.length == 1 ? '' : 's'} found',
                        style: TextStyle(
                          color: Colors
                              .grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // SEARCH
          // ----------------------------------------------------

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              8,
            ),
            child: TextField(
              controller:
                  searchController,
              decoration:
                  InputDecoration(
                hintText:
                    'Search name, location or contact',
                prefixIcon:
                    const Icon(
                  Icons.search,
                ),
                suffixIcon:
                    searchController
                            .text
                            .isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              searchController
                                  .clear();
                            },
                            icon:
                                const Icon(
                              Icons.clear,
                            ),
                          )
                        : null,
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // BLOOD GROUP FILTER
          // ----------------------------------------------------

          SizedBox(
            height: 55,
            child: ListView.builder(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              itemCount:
                  bloodGroups.length,
              itemBuilder:
                  (context, index) {
                final String group =
                    bloodGroups[index];

                final bool selected =
                    selectedBloodGroup ==
                        group;

                return Padding(
                  padding:
                      const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    label:
                        Text(group),
                    selected:
                        selected,
                    selectedColor:
                        Colors.red.shade100,
                    labelStyle:
                        TextStyle(
                      color: selected
                          ? Colors.red
                          : Colors.black87,
                      fontWeight:
                          FontWeight.w600,
                    ),
                    onSelected:
                        (value) {
                      if (!value) return;

                      setState(() {
                        selectedBloodGroup =
                            group;
                      });
                    },
                  ),
                );
              },
            ),
          ),

          // ----------------------------------------------------
          // VERIFICATION FILTER
          // ----------------------------------------------------

          SizedBox(
            height: 55,
            child: ListView.builder(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              itemCount:
                  verificationFilters
                      .length,
              itemBuilder:
                  (context, index) {
                final String filter =
                    verificationFilters[
                        index];

                final bool selected =
                    selectedVerification ==
                        filter;

                return Padding(
                  padding:
                      const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    avatar: filter ==
                            'Verified'
                        ? const Icon(
                            Icons.verified,
                            size: 18,
                          )
                        : filter ==
                                'Unverified'
                            ? const Icon(
                                Icons
                                    .pending_actions,
                                size: 18,
                              )
                            : null,
                    label:
                        Text(filter),
                    selected:
                        selected,
                    selectedColor:
                        filter ==
                                'Verified'
                            ? Colors.green
                                .shade100
                            : filter ==
                                    'Unverified'
                                ? Colors.orange
                                    .shade100
                                : Colors.red
                                    .shade100,
                    onSelected:
                        (value) {
                      if (!value) return;

                      setState(() {
                        selectedVerification =
                            filter;
                      });
                    },
                  ),
                );
              },
            ),
          ),

          // ----------------------------------------------------
          // DONOR LIST
          // ----------------------------------------------------

          Expanded(
            child: isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(
                      color: Colors.red,
                    ),
                  )
                : visibleDonors
                        .isEmpty
                    ? _emptyDonors()
                    : RefreshIndicator(
                        color:
                            Colors.red,
                        onRefresh:
                            _loadDonors,
                        child:
                            ListView
                                .builder(
                          padding:
                              const EdgeInsets
                                  .fromLTRB(
                            16,
                            8,
                            16,
                            25,
                          ),
                          itemCount:
                              visibleDonors
                                  .length,
                          itemBuilder:
                              (context,
                                  index) {
                            return _donorCard(
                              visibleDonors[
                                  index],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// EMERGENCY REQUEST LINK SCREEN
// ============================================================

class EmergencyRequestLinkScreen extends StatefulWidget {
  final String requestId;

  const EmergencyRequestLinkScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<EmergencyRequestLinkScreen> createState() =>
      _EmergencyRequestLinkScreenState();
}

class _EmergencyRequestLinkScreenState
    extends State<EmergencyRequestLinkScreen> {
  bool isLoading = true;
  bool isResponding = false;

  Map<String, dynamic>? requestData;

  String? assignmentId;
  String? currentResponse;

  @override
  void initState() {
    super.initState();

    _loadEmergencyRequest();
  }

  // ============================================================
  // LOAD EMERGENCY REQUEST
  // ============================================================

  Future<void> _loadEmergencyRequest() async {
    try {
      final User? user =
          FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
        });

        return;
      }

      // --------------------------------------------------------
      // GET EMERGENCY REQUEST
      // --------------------------------------------------------

      final DocumentSnapshot<Map<String, dynamic>>
          requestDocument =
          await FirebaseFirestore.instance
              .collection('emergencyRequests')
              .doc(widget.requestId)
              .get();

      if (!requestDocument.exists) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
          requestData = null;
        });

        return;
      }

      // --------------------------------------------------------
      // GET DONOR ASSIGNMENT
      // --------------------------------------------------------

      final QuerySnapshot<Map<String, dynamic>>
          assignmentSnapshot =
          await FirebaseFirestore.instance
              .collection('requestDonors')
              .where(
                'requestId',
                isEqualTo: widget.requestId,
              )
              .where(
                'donorId',
                isEqualTo: user.uid,
              )
              .limit(1)
              .get();

      String? foundAssignmentId;
      String? foundResponse;

      if (assignmentSnapshot.docs.isNotEmpty) {
        final assignment =
            assignmentSnapshot.docs.first;

        foundAssignmentId = assignment.id;

        foundResponse =
            assignment.data()['response']?.toString();
      }

      if (!mounted) return;

      setState(() {
        requestData = requestDocument.data();
        assignmentId = foundAssignmentId;
        currentResponse = foundResponse;
        isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Emergency request loading error: $e',
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to load emergency request.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // RESPOND TO REQUEST
  // ============================================================

  Future<void> _respondToRequest(
    String response,
  ) async {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    if (isResponding) {
      return;
    }

    setState(() {
      isResponding = true;
    });

    try {
      // --------------------------------------------------------
      // EXISTING ASSIGNMENT
      // --------------------------------------------------------

      if (assignmentId != null) {
        await FirebaseFirestore.instance
            .collection('requestDonors')
            .doc(assignmentId)
            .update({
          'response': response,
          'respondedAt':
              FieldValue.serverTimestamp(),
        });
      }

      // --------------------------------------------------------
      // NO EXISTING ASSIGNMENT
      // --------------------------------------------------------

      else {
        final DocumentReference assignmentReference =
            await FirebaseFirestore.instance
                .collection('requestDonors')
                .add({
          'requestId': widget.requestId,
          'donorId': user.uid,
          'response': response,
          'respondedAt':
              FieldValue.serverTimestamp(),
          'createdAt':
              FieldValue.serverTimestamp(),
        });

        assignmentId = assignmentReference.id;
      }

      // --------------------------------------------------------
      // UPDATE LOCAL STATE
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        currentResponse = response;
        isResponding = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response == 'accepted'
                ? 'Thank you for offering to help.'
                : 'Your response has been recorded.',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Emergency response error: $e',
      );

      if (!mounted) return;

      setState(() {
        isResponding = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to submit your response.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // FORMAT VALUE
  // ============================================================

  String _value(
    String key, {
    String fallback = 'Not available',
  }) {
    final value = requestData?[key];

    if (value == null) {
      return fallback;
    }

    final String text =
        value.toString().trim();

    if (text.isEmpty) {
      return fallback;
    }

    return text;
  }

  // ============================================================
  // INFORMATION ROW
  // ============================================================

  Widget _informationRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 9,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.red,
            size: 24,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESPONSE STATUS
  // ============================================================

  Widget _responseStatus() {
    if (currentResponse == null) {
      return const SizedBox.shrink();
    }

    final bool accepted =
        currentResponse == 'accepted';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 18,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accepted
            ? Colors.green.shade50
            : Colors.grey.shade100,
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: accepted
              ? Colors.green
              : Colors.grey,
        ),
      ),
      child: Row(
        children: [
          Icon(
            accepted
                ? Icons.check_circle
                : Icons.cancel,
            color: accepted
                ? Colors.green
                : Colors.grey,
            size: 28,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              accepted
                  ? 'You have offered to help with this request.'
                  : 'You declined this emergency request.',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ----------------------------------------------------------
    // LOADING
    // ----------------------------------------------------------

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Emergency Blood Request',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Colors.red,
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // REQUEST NOT FOUND
    // ----------------------------------------------------------

    if (requestData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Emergency Request',
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 70,
                  color: Colors.red,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Emergency request not found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Request ID: ${widget.requestId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 25),

                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'GO BACK',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // REQUEST DATA
    // ----------------------------------------------------------

    final String patientName =
        _value('patientName');

    final String bloodGroup =
        _value('bloodGroup');

    final String units =
        _value('unitsRequired');

    final String hospitalName =
        _value('hospitalName');

    final String hospitalLocation =
        _value('hospitalLocation');

    final String contactNumber =
        _value('contactNumber');

    final String urgency =
        _value('urgency');

    final String additionalInformation =
        _value(
      'additionalInformation',
      fallback: 'No additional information.',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Blood Request',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // --------------------------------------------------
            // HEADER
            // --------------------------------------------------

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.red.shade200,
                ),
              ),

              child: Column(
                children: [
                  const Icon(
                    Icons.bloodtype,
                    color: Colors.red,
                    size: 60,
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'URGENT BLOOD REQUEST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 23,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Blood Link Emergency Request',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // BLOOD GROUP
            // --------------------------------------------------

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius:
                    BorderRadius.circular(14),
              ),

              child: Column(
                children: [
                  const Text(
                    'BLOOD GROUP REQUIRED',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    bloodGroup,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    '$units unit(s) required',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // REQUEST DETAILS
            // --------------------------------------------------

            const Text(
              'Patient & Hospital Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              elevation: 2,
              child: Padding(
                padding:
                    const EdgeInsets.all(15),

                child: Column(
                  children: [
                    _informationRow(
                      icon: Icons.person,
                      title: 'Patient',
                      value: patientName,
                    ),

                    const Divider(),

                    _informationRow(
                      icon: Icons.local_hospital,
                      title: 'Hospital',
                      value: hospitalName,
                    ),

                    const Divider(),

                    _informationRow(
                      icon: Icons.location_on,
                      title: 'Location',
                      value:
                          hospitalLocation,
                    ),

                    const Divider(),

                    _informationRow(
                      icon: Icons.phone,
                      title: 'Contact',
                      value: contactNumber,
                    ),

                    const Divider(),

                    _informationRow(
                      icon: Icons.warning,
                      title: 'Urgency',
                      value: urgency,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // ADDITIONAL INFORMATION
            // --------------------------------------------------

            const Text(
              'Additional Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(12),
              ),

              child: Text(
                additionalInformation,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // CURRENT RESPONSE
            // --------------------------------------------------

            _responseStatus(),

            // --------------------------------------------------
            // RESPONSE BUTTONS
            // --------------------------------------------------

            if (currentResponse == null) ...[
              SizedBox(
                width: double.infinity,
                height: 55,

                child: ElevatedButton.icon(
                  onPressed: isResponding
                      ? null
                      : () {
                          _respondToRequest(
                            'accepted',
                          );
                        },

                  icon: const Icon(
                    Icons.volunteer_activism,
                  ),

                  label: const Text(
                    'I CAN HELP',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.green,
                    foregroundColor:
                        Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 50,

                child: OutlinedButton.icon(
                  onPressed: isResponding
                      ? null
                      : () {
                          _respondToRequest(
                            'declined',
                          );
                        },

                  icon: const Icon(
                    Icons.close,
                  ),

                  label: const Text(
                    'I CAN\'T HELP',
                  ),

                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.red,
                  ),
                ),
              ),
            ],

            if (isResponding) ...[
              const SizedBox(height: 20),

              const Center(
                child:
                    CircularProgressIndicator(
                  color: Colors.red,
                ),
              ),
            ],

            const SizedBox(height: 25),

            // --------------------------------------------------
            // MEDICAL DISCLAIMER
            // --------------------------------------------------

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius:
                    BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.shade200,
                ),
              ),

              child: const Text(
                'Blood Link helps connect donors with '
                'blood requests. Final blood compatibility '
                'and donation eligibility must be confirmed '
                'by an authorized medical professional or '
                'blood bank.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}