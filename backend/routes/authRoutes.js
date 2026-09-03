const express = require('express');
const router = express.Router();
const admin = require('firebase-admin');

// Simple test endpoint
router.get('/test', (req, res) => {
  res.json({ message: 'Auth routes are working!' });
});

// Login endpoint
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    console.log('🔐 LOGIN: Received credentials for:', email);

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required'
      });
    }

    // Extract name from email for the actual user
    const emailName = email.split('@')[0];
    const displayName = emailName.charAt(0).toUpperCase() + emailName.slice(1);

    // ✅ Encode user data in the token (dynamic approach)
    const userData = {
      email: email,
      username: emailName,
      name_en: displayName,
      displayName: displayName,
      uid: 'dev-user-id'
    };
    
    console.log('🔐 LOGIN: User data to encode:', userData);
    
    // Simple base64 encoding for development
    const tokenPayload = Buffer.from(JSON.stringify(userData)).toString('base64');
    const token = `dev-token-${tokenPayload}`;
    
    console.log('🔐 LOGIN: Generated token:', token.substring(0, 50) + '...');

    res.json({
      success: true,
      token: token, // ✅ Now using the encoded token, not hardcoded
      message: 'Login successful! (Backend received credentials)',
      user: userData
    });
    
    console.log('✅ LOGIN: Response sent successfully');
  } catch (error) {
    console.error('❌ LOGIN ERROR:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error during login'
    });
  }
});

module.exports = router;