const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin FIRST
const serviceAccount = require('./service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Create Express app AFTER Firebase
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors({
  origin: true, // Allow all origins for testing
  credentials: true
}));
app.use(express.json());

// Import routes AFTER app is created
const authenticate = require('./middleware/auth');
const casesRoutes = require('./routes/casesRoutes');
const chatRoutes = require('./routes/chatroutes');

// Public routes (no authentication needed)
app.use('/api/auth', require('./routes/authRoutes'));

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'Backend is running!' });
});

// Protected routes (authentication required)
app.use('/api/user', authenticate, require('./routes/userRoutes'));
app.use('/api/cases', authenticate, casesRoutes);
app.use('/api/chats', authenticate, chatRoutes); // ← MOVED THIS LINE

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Backend server running on port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/api/health`);
});