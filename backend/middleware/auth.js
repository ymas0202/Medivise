const admin = require('firebase-admin');

const authenticate = async (req, res, next) => {
  try {
    console.log('🔐 Auth Middleware: Checking token...');
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.log('❌ No Bearer token in header');
      return res.status(401).json({ 
        success: false, 
        message: 'No token provided' 
      });
    }

    const token = authHeader.split('Bearer ')[1];
    console.log('🔐 Token received:', token.substring(0, 30) + '...');
    
    // ✅ Handle development token with encoded user data
    if (token.startsWith('dev-token-')) {
      console.log('🔍 Development token detected, decoding user data...');
      
      try {
        // Extract and decode the user data from token
        const tokenPayload = token.replace('dev-token-', '');
        const userDataJson = Buffer.from(tokenPayload, 'base64').toString('utf8');
        const userData = JSON.parse(userDataJson);
        
        console.log('✅ Decoded user data:', userData);
        
        req.user = userData;
        return next();
      } catch (decodeError) {
        console.log('❌ Failed to decode development token:', decodeError);
        return res.status(401).json({ 
          success: false, 
          message: 'Invalid development token' 
        });
      }
    }
    
    // Real token verification for production
    console.log('🔐 Verifying real Firebase token...');
    const decodedToken = await admin.auth().verifyIdToken(token);
    console.log('✅ Real token verified for user:', decodedToken.uid);
    req.user = decodedToken;
    next();
    
  } catch (error) {
    console.log('❌ Token verification failed:', error.message);
    res.status(401).json({ 
      success: false, 
      message: 'Invalid token: ' + error.message 
    });
  }
};

module.exports = authenticate;