const express = require('express');
const router = express.Router();
const admin = require('firebase-admin');
const authenticate = require('../middleware/auth'); // ← ADD THIS

// Get user profile
router.get('/profile', authenticate, async (req, res) => { // ← ADD authenticate
  try {
    console.log('🔍 Profile endpoint called');
    
    // User data from the auth middleware (contains email)
    const userData = req.user;
    console.log('🔍 User data from token:', userData);
    
    let userRecord;
    let userEmail = userData.email;
    let username = 'Paramedic Name';
    let nameEn = 'Paramedic Name';
    let displayName = 'Paramedic';

    // Handle development user vs real user
    if (userData.uid === 'dev-user-id') {
      console.log('🔍 Development user detected');
      
      // ✅ TRY TO GET USER DATA FROM FIRESTORE FIRST
      try {
        console.log('🔍 Searching Firestore for user with email:', userEmail);
        
        // Query Firestore for a user with this email
        const usersRef = admin.firestore().collection('users');
        const snapshot = await usersRef.where('email', '==', userEmail).get();
        
        if (!snapshot.empty) {
          console.log('✅ Found user in Firestore');
          const userDoc = snapshot.docs[0];
          const userDataFromFirestore = userDoc.data();
          
          console.log('🔍 Firestore user data:', userDataFromFirestore);
          
          // Use the actual data from Firestore
          username = userDataFromFirestore.username || userDataFromFirestore.name_en || username;
          nameEn = userDataFromFirestore.name_en || userDataFromFirestore.username || nameEn;
          displayName = userDataFromFirestore.displayName || userDataFromFirestore.name_en || displayName;
          
          console.log('✅ Using Firestore data:', { username, nameEn, displayName });
        } else {
          console.log('❌ No user found in Firestore for email:', userEmail);
          console.log('💡 Using email-based name as fallback');
          
          // Fallback to email-based name
          const emailName = userEmail.split('@')[0];
          username = emailName;
          nameEn = emailName.charAt(0).toUpperCase() + emailName.slice(1);
          displayName = nameEn;
        }
      } catch (firestoreError) {
        console.log('❌ Firestore query error:', firestoreError);
        // Fallback to email-based name
        const emailName = userEmail.split('@')[0];
        username = emailName;
        nameEn = emailName.charAt(0).toUpperCase() + emailName.slice(1);
        displayName = nameEn;
      }
      
      userRecord = {
        uid: 'dev-user-id',
        email: userEmail,
        emailVerified: true
      };
      
    } else {
      // Real user from Firebase Auth
      console.log('🔍 Fetching real user from Firebase Auth...');
      userRecord = await admin.auth().getUser(userData.uid);
      userEmail = userRecord.email;
      
      // Try to get user data from Firestore
      try {
        const userDoc = await admin.firestore().collection('users').doc(userData.uid).get();
        if (userDoc.exists) {
          const firestoreData = userDoc.data();
          username = firestoreData?.username || username;
          nameEn = firestoreData?.name_en || nameEn;
          displayName = firestoreData?.displayName || displayName;
        }
      } catch (firestoreError) {
        console.log('❌ Firestore error:', firestoreError);
      }
    }
    
    res.json({
      success: true,
      user: {
        uid: userRecord.uid,
        email: userEmail,
        username: username,
        name_en: nameEn,
        displayName: displayName,
        emailVerified: userRecord.emailVerified || true
      }
    });
    
    console.log('✅ Profile response sent with data from Firestore');
  } catch (error) {
    console.error('❌ Profile endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error fetching user profile: ' + error.message 
    });
  }
});

// Update email
router.put('/email', authenticate, async (req, res) => { // ← ADD authenticate
  try {
    console.log('📧 Updating user email');
    const { newEmail, currentPassword } = req.body;
    const userId = req.user.uid;

    if (!newEmail || !currentPassword) {
      return res.status(400).json({
        success: false,
        message: 'New email and current password are required'
      });
    }

    // Note: Firebase Admin SDK doesn't have password verification
    // You would need to use Firebase Auth REST API or client SDK for this
    // For now, we'll proceed with the email update
    
    console.log('📧 Updating email for user:', userId, 'to:', newEmail);

    // Update email in Firebase Auth
    await admin.auth().updateUser(userId, { 
      email: newEmail,
      emailVerified: false // Email verification will be required
    });
    
    // Update email in Firestore if user document exists
    try {
      await admin.firestore().collection('users').doc(userId).update({
        email: newEmail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log('✅ Email updated in Firestore');
    } catch (firestoreError) {
      console.log('⚠️ Could not update Firestore (user document may not exist):', firestoreError);
    }

    console.log('✅ Email updated successfully');

    res.json({
      success: true,
      message: 'Email updated successfully! Please check your new email for verification.'
    });
  } catch (error) {
    console.error('❌ Update email error:', error);
    
    // Handle specific Firebase Auth errors
    if (error.code === 'auth/email-already-exists') {
      return res.status(400).json({ 
        success: false, 
        message: 'This email is already in use by another account.' 
      });
    }
    
    if (error.code === 'auth/invalid-email') {
      return res.status(400).json({ 
        success: false, 
        message: 'The email address is invalid.' 
      });
    }
    
    res.status(400).json({ 
      success: false, 
      message: 'Error updating email: ' + error.message 
    });
  }
});

// Update password
router.put('/password', authenticate, async (req, res) => { // ← ADD authenticate
  try {
    console.log('🔑 Updating user password');
    const { newPassword } = req.body;
    const userId = req.user.uid;

    if (!newPassword) {
      return res.status(400).json({
        success: false,
        message: 'New password is required'
      });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters long'
      });
    }

    console.log('🔑 Updating password for user:', userId);

    // Update password in Firebase Auth
    await admin.auth().updateUser(userId, { 
      password: newPassword 
    });

    // Update timestamp in Firestore if user document exists
    try {
      await admin.firestore().collection('users').doc(userId).update({
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (firestoreError) {
      console.log('⚠️ Could not update Firestore:', firestoreError);
    }

    console.log('✅ Password updated successfully');

    res.json({
      success: true,
      message: 'Password updated successfully!'
    });
  } catch (error) {
    console.error('❌ Update password error:', error);
    
    if (error.code === 'auth/weak-password') {
      return res.status(400).json({ 
        success: false, 
        message: 'Password is too weak. Please choose a stronger password.' 
      });
    }
    
    res.status(400).json({ 
      success: false, 
      message: 'Error updating password: ' + error.message 
    });
  }
});

module.exports = router;