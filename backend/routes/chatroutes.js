const express = require('express');
const router = express.Router();
const admin = require('firebase-admin');
const authenticate = require('../middleware/auth');
const fetch = require('node-fetch');

// Get chat messages
router.get('/:chatId/messages', authenticate, async (req, res) => {
  try {
    const userId = req.user.uid;
    const { chatId } = req.params;

    // Verify user has access to this chat
    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(chatId)
      .get();

    if (!caseDoc.exists || caseDoc.data().uid !== userId) {
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    // Get messages
    const messagesSnapshot = await admin.firestore()
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .orderBy('timestamp', 'asc')
      .get();

    const messages = messagesSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      timestamp: doc.data().timestamp?.toDate?.() || doc.data().timestamp,
    }));

    res.json({
      success: true,
      messages: messages,
    });

  } catch (error) {
    console.error('Get chat messages error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error fetching messages' 
    });
  }
});

// Send a message
router.post('/:chatId/messages', authenticate, async (req, res) => {
  try {
    const userId = req.user.uid;
    const { chatId } = req.params;
    const { text, role = 'user' } = req.body;

    if (!text || text.trim().length === 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Message text is required' 
      });
    }

    // Verify user has access to this chat
    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(chatId)
      .get();

    if (!caseDoc.exists || caseDoc.data().uid !== userId) {
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    // Add message to Firestore
    const messageRef = await admin.firestore()
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .add({
        role: role,
        text: text.trim(),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.status(201).json({
      success: true,
      messageId: messageRef.id,
    });

  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error sending message' 
    });
  }
});

// Get AI response - SIMPLIFIED VERSION
router.post('/:chatId/ai-response', authenticate, async (req, res) => {
  try {
    const userId = req.user.uid;
    const { chatId } = req.params;
    const { userMessage, isInitialGreeting = false } = req.body;

    // Verify user has access to this chat
    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(chatId)
      .get();

    if (!caseDoc.exists || caseDoc.data().uid !== userId) {
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    const caseData = caseDoc.data();
    
    // SIMPLE case summary
    const caseSummary = `
Patient: ${caseData.conditionNameEn || 'Cardiac case'}
Heart Rate: ${caseData.heartRate || 'N/A'} bpm
Chest Pain: ${caseData.hasChestPain ? 'Yes' : 'No'}
Smoker: ${caseData.isSmoker ? 'Yes' : 'No'}
ECG: ${caseData.ecgContent ? 'Data available' : 'No data'}
`;

    let prompt;
    if (isInitialGreeting) {
      prompt = `Based on this patient case: ${caseSummary}

Provide:
1. Diagnosis (2-5 words)
2. Emergency treatment steps
3. Brief analysis

Be direct and concise.`;
    } else {
      // SIMPLE prompt for regular questions
      prompt = `Patient case: ${caseSummary}

User question: ${userMessage}

Answer directly and helpfully. Keep it under 100 words. Be practical for emergency medical care.`;
    }

    // Call OpenAI API
    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o",
        messages: [
          {
            role: "system",
            content: "You are a helpful medical assistant for paramedics. Answer questions directly and practically. Keep responses clear and concise."
          },
          { role: "user", content: prompt },
        ],
        temperature: 0.7,
        max_tokens: 300,
      }),
    });

    if (!openaiResponse.ok) {
      throw new Error(`OpenAI API error: ${openaiResponse.status}`);
    }

    const openaiData = await openaiResponse.json();
    let botReply = openaiData.choices[0].message.content.trim();

    // Save bot response
    const messageRef = await admin.firestore()
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .add({
        role: 'bot',
        text: botReply,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    // For initial greeting, extract and save data
    if (isInitialGreeting) {
      const updateData = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Simple extraction - take first line as diagnosis
      const lines = botReply.split('\n').filter(line => line.trim().length > 0);
      if (lines.length > 0) {
        const firstLine = lines[0].replace(/^[0-9].\s*/, '').trim(); // Remove "1. " if present
        if (firstLine.length > 0 && firstLine.length < 50) {
          updateData.diagnosisEn = firstLine;
        }
      }

      // Take the rest as treatment/analysis
      if (lines.length > 1) {
        updateData.treatment_en = lines.slice(1).join('\n');
      }

      await admin.firestore()
        .collection('cases')
        .doc(chatId)
        .update(updateData);
    }

    res.json({
      success: true,
      botReply: botReply,
      messageId: messageRef.id,
    });

  } catch (error) {
    console.error('AI response error:', error);
    
    // Simple fallback
    const fallbackResponse = isInitialGreeting 
      ? "I'll help analyze this cardiac case. What specific information do you need?"
      : "I'm here to help with medical questions. What do you need to know?";

    try {
      const messageRef = await admin.firestore()
        .collection('chats')
        .doc(req.params.chatId)
        .collection('messages')
        .add({
          role: 'bot',
          text: fallbackResponse,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

      res.json({
        success: true,
        botReply: fallbackResponse,
        messageId: messageRef.id,
      });
    } catch (fallbackError) {
      res.status(500).json({ 
        success: false, 
        message: 'Error generating response' 
      });
    }
  }
});

module.exports = router;