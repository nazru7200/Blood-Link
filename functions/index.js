const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

setGlobalOptions({
  maxInstances: 10,
});

// ============================================================
// BLOOD LINK - EMERGENCY REQUEST NOTIFICATION
// ============================================================

exports.notifyMatchingDonors = onDocumentCreated(
    "emergencyRequests/{requestId}",
    async (event) => {
      const snapshot = event.data;

      if (!snapshot) {
        logger.info("No emergency request data found.");
        return;
      }

      const request = snapshot.data();
      const requestId = event.params.requestId;

      logger.info("New emergency request:", {
        requestId: requestId,
        bloodGroup: request.bloodGroup,
        unitsRequired: request.unitsRequired,
      });

      // --------------------------------------------------------
      // Find donors with matching blood group
      // --------------------------------------------------------

      const donorsSnapshot = await db
          .collection("donors")
          .where("bloodGroup", "==", request.bloodGroup)
          .where("availability", "==", true)
          .get();

      if (donorsSnapshot.empty) {
        logger.info("No available matching donors found.");
        return;
      }

      const tokens = [];

      donorsSnapshot.forEach((donorDoc) => {
        const donor = donorDoc.data();

        if (donor.fcmToken) {
          tokens.push(donor.fcmToken);
        }
      });

      if (tokens.length === 0) {
        logger.info("Matching donors found, but no FCM tokens.");
        return;
      }

      // --------------------------------------------------------
      // Notification
      // --------------------------------------------------------

      const message = {
        notification: {
          title: "🚨 Blood Emergency",
          body:
            `${request.bloodGroup} blood required at ` +
            `${request.hospitalName || "hospital"}`,
        },

        data: {
          requestId: requestId,
          bloodGroup: request.bloodGroup || "",
          unitsRequired: String(request.unitsRequired || ""),
          hospitalName: request.hospitalName || "",
          hospitalLocation: request.hospitalLocation || "",
          urgency: request.urgency || "",
          type: "blood_emergency",
        },

        tokens: tokens,
      };

      const response = await admin
          .messaging()
          .sendEachForMulticast(message);

      logger.info("Emergency notifications sent.", {
        successful: response.successCount,
        failed: response.failureCount,
      });
    },
);