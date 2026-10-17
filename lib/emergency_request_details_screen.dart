import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EmergencyRequestDetailsScreen extends StatefulWidget {
  final String requestId;

  const EmergencyRequestDetailsScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<EmergencyRequestDetailsScreen> createState() =>
      _EmergencyRequestDetailsScreenState();
}

class _EmergencyRequestDetailsScreenState
    extends State<EmergencyRequestDetailsScreen> {
  bool _isResponding = false;

  // ============================================================
  // DONOR RESPONSE
  // ============================================================

  Future<void> _respondToRequest(String response) async {
    if (_isResponding) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'Please login to Blood Link before responding.',
      );
      return;
    }

    setState(() {
      _isResponding = true;
    });

    try {
      // --------------------------------------------------------
      // GET DONOR INFORMATION
      // --------------------------------------------------------

      final donorSnapshot = await FirebaseFirestore.instance
          .collection('donors')
          .doc(user.uid)
          .get();

      if (!donorSnapshot.exists) {
        throw Exception(
          'Donor profile not found.',
        );
      }

      final donorData =
          donorSnapshot.data() as Map<String, dynamic>;

      final donorName =
          donorData['name']?.toString() ?? 'Unknown Donor';

      final donorPhone =
          donorData['phone']?.toString() ?? '';

      final bloodGroup =
          donorData['bloodGroup']?.toString() ?? 'Unknown';

      final location =
          donorData['location']?.toString() ?? 'Unknown';

      // --------------------------------------------------------
      // CHECK EMERGENCY REQUEST
      // --------------------------------------------------------

      final requestSnapshot = await FirebaseFirestore.instance
          .collection('emergencyRequests')
          .doc(widget.requestId)
          .get();

      if (!requestSnapshot.exists) {
        throw Exception(
          'Emergency request not found.',
        );
      }

      final requestData =
          requestSnapshot.data() as Map<String, dynamic>;

      final requestStatus =
          requestData['status']?.toString() ?? 'Searching';

      if (requestStatus.toLowerCase() != 'searching' &&
          requestStatus.toLowerCase() != 'active') {
        throw Exception(
          'This emergency request is no longer active.',
        );
      }

      // --------------------------------------------------------
      // CREATE DONOR RESPONSE
      // --------------------------------------------------------

      final assignmentId =
          '${widget.requestId}_${user.uid}';

      await FirebaseFirestore.instance
          .collection('requestDonors')
          .doc(assignmentId)
          .set(
        {
          'requestId': widget.requestId,
          'donorId': user.uid,
          'donorName': donorName,
          'donorPhone': donorPhone,
          'bloodGroup': bloodGroup,
          'location': location,
          'response': response,
          'respondedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      // --------------------------------------------------------
      // SUCCESS MESSAGE
      // --------------------------------------------------------

      if (response == 'accepted') {
        _showMessage(
          'Thank you! Your response has been sent to the organization.',
        );
      } else {
        _showMessage(
          'Your response has been sent to the organization.',
        );
      }

      // Return to previous screen after response.
      await Future.delayed(
        const Duration(milliseconds: 800),
      );

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Unable to send response: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResponding = false;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // INFORMATION ROW
  // ============================================================

  Widget _informationRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.red,
              size: 21,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Blood Request',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),

      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('emergencyRequests')
            .doc(widget.requestId)
            .snapshots(),

        builder: (context, snapshot) {
          // ------------------------------------------------------
          // LOADING
          // ------------------------------------------------------

          if (snapshot.connectionState ==
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

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      'Unable to load emergency request.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ------------------------------------------------------
          // REQUEST NOT FOUND
          // ------------------------------------------------------

          if (!snapshot.hasData ||
              !snapshot.data!.exists) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 60,
                      color: Colors.grey,
                    ),

                    SizedBox(height: 15),

                    Text(
                      'Emergency request not found.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 8),

                    Text(
                      'The request may have been removed or the link may be invalid.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ------------------------------------------------------
          // REQUEST DATA
          // ------------------------------------------------------

          final requestData =
              snapshot.data!.data()
                  as Map<String, dynamic>;

          final patientName =
              requestData['patientName']
                  ?.toString() ??
                  'Patient';

          final bloodGroup =
              requestData['bloodGroup']
                  ?.toString() ??
                  'Unknown';

          final units =
              requestData['unitsRequired']
                  ?.toString() ??
                  '0';

          final hospitalName =
              requestData['hospitalName']
                  ?.toString() ??
                  'Hospital';

          final hospitalLocation =
              requestData['hospitalLocation']
                  ?.toString() ??
                  'Unknown';

          final contactNumber =
              requestData['contactNumber']
                  ?.toString() ??
                  'Not available';

          final urgency =
              requestData['urgency']
                  ?.toString() ??
                  'Normal';

          final status =
              requestData['status']
                  ?.toString() ??
                  'Searching';

          final isActive =
              status.toLowerCase() == 'searching' ||
              status.toLowerCase() == 'active';

          // ------------------------------------------------------
          // UI
          // ------------------------------------------------------

          return SingleChildScrollView(
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
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius:
                        BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.red.shade100,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red
                                  .withValues(alpha: 0.25),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bloodtype,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),

                      const SizedBox(height: 15),

                      const Text(
                        'EMERGENCY BLOOD REQUEST',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        '$bloodGroup Blood Required',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: urgency
                                      .toLowerCase() ==
                                  'critical'
                              ? Colors.red
                              : Colors.orange,
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                        child: Text(
                          urgency.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // ==================================================
                // PATIENT INFORMATION
                // ==================================================

                const Text(
                  'Patient Information',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Card(
                  elevation: 2,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _informationRow(
                          Icons.person,
                          'Patient Name',
                          patientName,
                        ),

                        _informationRow(
                          Icons.water_drop,
                          'Blood Group',
                          bloodGroup,
                        ),

                        _informationRow(
                          Icons.bloodtype,
                          'Units Required',
                          '$units Unit(s)',
                        ),

                        _informationRow(
                          Icons.warning_amber,
                          'Urgency',
                          urgency.toUpperCase(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // ==================================================
                // HOSPITAL INFORMATION
                // ==================================================

                const Text(
                  'Hospital Information',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Card(
                  elevation: 2,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _informationRow(
                          Icons.local_hospital,
                          'Hospital',
                          hospitalName,
                        ),

                        _informationRow(
                          Icons.location_on,
                          'Location',
                          hospitalLocation,
                        ),

                        _informationRow(
                          Icons.phone,
                          'Contact',
                          contactNumber,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // ==================================================
                // REQUEST STATUS
                // ==================================================

                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isActive
                            ? Icons
                                .radio_button_checked
                            : Icons.info_outline,
                        color: isActive
                            ? Colors.green
                            : Colors.grey,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          isActive
                              ? 'This emergency request is currently active.'
                              : 'This emergency request is no longer active.',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.w600,
                            color: isActive
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // ==================================================
                // RESPONSE BUTTONS
                // ==================================================

                if (isActive) ...[
                  const Text(
                    'Can you help?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Your response will be sent to the organization handling this emergency.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ------------------------------------------------
                  // I CAN HELP
                  // ------------------------------------------------

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isResponding
                          ? null
                          : () {
                              _respondToRequest(
                                'accepted',
                              );
                            },
                      icon: _isResponding
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
                              Icons.check_circle,
                            ),
                      label: const Text(
                        'I CAN HELP',
                        style: TextStyle(
                          fontSize: 16,
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
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 16,
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

                  const SizedBox(height: 12),

                  // ------------------------------------------------
                  // I CAN'T HELP
                  // ------------------------------------------------

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isResponding
                          ? null
                          : () {
                              _respondToRequest(
                                'declined',
                              );
                            },
                      icon: const Icon(
                        Icons.cancel_outlined,
                      ),
                      label: const Text(
                        'I CAN\'T HELP',
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
                        side:
                            const BorderSide(
                          color: Colors.red,
                        ),
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 16,
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
                ] else ...[
                  // ------------------------------------------------
                  // CLOSED REQUEST
                  // ------------------------------------------------

                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 45,
                          color: Colors.grey,
                        ),

                        SizedBox(height: 10),

                        Text(
                          'Response Closed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        SizedBox(height: 6),

                        Text(
                          'This emergency request is no longer accepting responses.',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 25),

                // ==================================================
                // PRIVACY NOTE
                // ==================================================

                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                      ),

                      SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          'Please respond only if you are genuinely available to help. The organization will contact you if your response is accepted.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }
}