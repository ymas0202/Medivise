const express = require('express');
const router = express.Router();
const admin = require('firebase-admin');
const authenticate = require('../middleware/auth');
const fetch = require('node-fetch');

// Helper function to safely format dates for Flutter
function safeDateForFlutter(firestoreTimestamp) {
  if (!firestoreTimestamp) return null;
  
  // If it's a Firestore Timestamp object
  if (firestoreTimestamp.toDate && typeof firestoreTimestamp.toDate === 'function') {
    return firestoreTimestamp.toDate().toISOString(); // Convert to ISO string for Flutter
  }
  
  // If it's already a Date object
  if (firestoreTimestamp instanceof Date) {
    return firestoreTimestamp.toISOString();
  }
  
  // If it's already a string, return as-is
  return firestoreTimestamp;
}

// Get recent cases for the current user (top 5 most recent) - HOMEPAGE
router.get('/recent', authenticate, async (req, res) => {
  try {
    console.log('🔍 Recent cases endpoint called');
    const userId = req.user.uid;
    const userEmail = req.user.email;
    
    console.log('🔍 Fetching cases for user:', userEmail);

    let cases = [];

    // ✅ Handle development user vs real user
    if (userId === 'dev-user-id') {
      console.log('🔍 Development user detected, fetching cases from Firestore...');
      
      try {
        // Query Firestore for cases assigned to this user
        const casesRef = admin.firestore().collection('cases');
        const snapshot = await casesRef
          .where('uid', '==', userId)
          .orderBy('recordedAt', 'desc')
          .limit(5)
          .get();
        
        if (!snapshot.empty) {
          console.log(`✅ Found ${snapshot.size} cases in Firestore`);
          
          cases = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
              id: doc.id,
              patientFirstName: data.patientFirstName || '',
              patientLastName: data.patientLastName || '',
              conditionNameEn: data.conditionNameEn || 'Unknown Condition',
              recordedAt: safeDateForFlutter(data.recordedAt) || new Date().toISOString(), // ← FIXED
            };
          });
          
          console.log('✅ Cases data:', cases);
        } else {
          console.log('ℹ️ No cases found for user in Firestore');
        }
      } catch (firestoreError) {
        console.log('❌ Firestore error:', firestoreError);
        return res.status(500).json({ 
          success: false, 
          message: 'Error fetching cases from database' 
        });
      }
    } else {
      // For real users
      console.log('🔍 Real user detected, fetching cases...');
      try {
        const casesRef = admin.firestore().collection('cases');
        const snapshot = await casesRef
          .where('uid', '==', userId)
          .orderBy('recordedAt', 'desc')
          .limit(5)
          .get();
        
        if (!snapshot.empty) {
          cases = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
              id: doc.id,
              patientFirstName: data.patientFirstName || '',
              patientLastName: data.patientLastName || '',
              conditionNameEn: data.conditionNameEn || 'Unknown Condition',
              recordedAt: safeDateForFlutter(data.recordedAt) || new Date().toISOString(), // ← FIXED
            };
          });
        }
      } catch (error) {
        console.log('❌ Firestore error for real user:', error);
        return res.status(500).json({ 
          success: false, 
          message: 'Error fetching cases' 
        });
      }
    }
    
    res.json({
      success: true,
      cases: cases,
      count: cases.length
    });
    
    console.log(`✅ Sent ${cases.length} recent cases to client`);
  } catch (error) {
    console.error('❌ Recent cases endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error fetching recent cases: ' + error.message 
    });
  }
});

// Get all cases for user (history page) - with sorting
router.get('/history', authenticate, async (req, res) => {
  try {
    console.log('📋 History cases endpoint called');
    const userId = req.user.uid;
    const userEmail = req.user.email;
    const { sort = 'desc' } = req.query;
    
    console.log(`🔍 Fetching ALL cases for user: ${userEmail}, sort: ${sort}`);

    let cases = [];

    const targetUserId = userId === 'dev-user-id' ? 'dev-user-id' : userId;
    
    try {
      const casesRef = admin.firestore().collection('cases');
      const snapshot = await casesRef
        .where('uid', '==', targetUserId)
        .orderBy('recordedAt', sort === 'desc' ? 'desc' : 'asc')
        .get();
      
      if (!snapshot.empty) {
        console.log(`✅ Found ${snapshot.size} total cases in Firestore for history`);
        
        cases = snapshot.docs.map(doc => {
          const data = doc.data();
          return {
            id: doc.id,
            patientFirstName: data.patientFirstName || '',
            patientLastName: data.patientLastName || '',
            conditionNameEn: data.conditionNameEn || 'Unknown Condition',
            recordedAt: safeDateForFlutter(data.recordedAt) || new Date().toISOString(), // ← FIXED
            uid: data.uid,
          };
        });
        
        console.log(`✅ Prepared ${cases.length} cases for history page`);
      } else {
        console.log('ℹ️ No cases found for user in Firestore (history)');
      }
    } catch (firestoreError) {
      console.log('❌ Firestore error in history endpoint:', firestoreError);
      return res.status(500).json({ 
        success: false, 
        message: 'Error fetching cases history from database' 
      });
    }
    
    res.json({
      success: true,
      cases: cases,
      count: cases.length
    });
    
  } catch (error) {
    console.error('❌ History cases endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error fetching cases history: ' + error.message 
    });
  }
});

// Delete a specific case
router.delete('/:caseId', authenticate, async (req, res) => {
  try {
    console.log('🗑️ Delete case endpoint called');
    const { caseId } = req.params;
    const userId = req.user.uid;
    
    console.log(`🔍 Attempting to delete case: ${caseId} for user: ${userId}`);

    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .get();
    
    if (!caseDoc.exists) {
      console.log('❌ Case not found:', caseId);
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }
    
    const caseData = caseDoc.data();
    if (caseData.uid !== userId) {
      console.log('❌ Access denied - user does not own this case');
      return res.status(403).json({ 
        success: false, 
        message: 'Access denied - you do not own this case' 
      });
    }
    
    await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .delete();
    
    console.log('✅ Case deleted successfully:', caseId);
    
    res.json({ 
      success: true, 
      message: 'Case deleted successfully' 
    });
  } catch (error) {
    console.error('❌ Delete case endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error deleting case: ' + error.message 
    });
  }
});

// Create a new case (for NewDiagnosisPage)
router.post('/', authenticate, async (req, res) => {
  try {
    console.log('📝 Creating new case');
    const userId = req.user.uid;
    const userEmail = req.user.email;
    
    const {
      patientFirstName,
      patientLastName,
      patientDob,
      isSmoker,
      hasChestPain,
      hasFamilyHistory,
      additionalNotes,
      ecgContent,
      ecgFileName,
      conditionNameEn
    } = req.body;

    console.log('🔍 Case data received:', {
      patientFirstName,
      patientLastName,
      patientDob,
      isSmoker,
      hasChestPain,
      hasFamilyHistory,
      additionalNotes: additionalNotes ? 'Provided' : 'Not provided',
      ecgContent: ecgContent ? `Length: ${ecgContent.length} chars` : 'Not provided', 
      ecgFileName: ecgFileName || 'Not provided',
      conditionNameEn,
      userEmail
    });

    if (!patientFirstName || !patientLastName) {
      return res.status(400).json({
        success: false,
        message: 'Patient first name and last name are required'
      });
    }

    const caseData = {
      uid: userId,
      patientFirstName: patientFirstName.trim(),
      patientLastName: patientLastName.trim(),
      patientDob: patientDob || null,
      isSmoker: isSmoker || null,
      hasChestPain: hasChestPain || null,
      hasFamilyHistory: hasFamilyHistory || null,
      additionalNotes: additionalNotes || null,
      ecgContent: ecgContent || null,  
      ecgFileName: ecgFileName || null, 
      conditionNameEn: conditionNameEn || 'Analysis in Progress...', // ← UPDATED
      recordedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'created',
      createdBy: userEmail,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    const caseRef = await admin.firestore().collection('cases').add(caseData);

    console.log('✅ Case created with ID:', caseRef.id);

    res.status(201).json({
      success: true,
      caseId: caseRef.id,
      message: 'Case created successfully'
    });

  } catch (error) {
    console.error('❌ Create case endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error creating case: ' + error.message 
    });
  }
});

// Update case with analysis results
router.put('/:caseId', authenticate, async (req, res) => {
  try {
    console.log('📝 Updating case:', req.params.caseId);
    const userId = req.user.uid;
    const { caseId } = req.params;
    const updateData = req.body;

    console.log('🔍 Update data received:', updateData);

    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .get();

    if (!caseDoc.exists) {
      console.log('❌ Case not found:', caseId);
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    if (caseDoc.data().uid !== userId) {
      console.log('❌ Access denied - user does not own this case');
      return res.status(403).json({ 
        success: false, 
        message: 'Access denied' 
      });
    }

    const updateFields = {
      ...updateData,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .update(updateFields);

    console.log('✅ Case updated successfully:', caseId);

    res.json({
      success: true,
      message: 'Case updated successfully'
    });

  } catch (error) {
    console.error('❌ Update case endpoint error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error updating case: ' + error.message 
    });
  }
});

// Get specific case details with analysis
router.get('/:caseId', authenticate, async (req, res) => {
  try {
    console.log('📋 Fetching case details for:', req.params.caseId);
    const userId = req.user.uid;
    const { caseId } = req.params;

    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .get();

    if (!caseDoc.exists) {
      console.log('❌ Case not found:', caseId);
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    const caseData = caseDoc.data();
    
    if (caseData.uid !== userId) {
      console.log('❌ Access denied - user does not own this case');
      return res.status(403).json({ 
        success: false, 
        message: 'Access denied' 
      });
    }

    console.log('✅ Case details fetched successfully');

    // Return all case data with safe date formatting
    res.json({
      success: true,
      case: {
        id: caseDoc.id,
        ...caseData,
        // Use safe date formatting for all dates
        recordedAt: safeDateForFlutter(caseData.recordedAt),
        analyzedAt: safeDateForFlutter(caseData.analyzedAt),
        updatedAt: safeDateForFlutter(caseData.updatedAt),
      }
    });

  } catch (error) {
    console.error('❌ Get case details error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error fetching case details: ' + error.message 
    });
  }
});

// Analyze case with full context (ECG + patient data + notes)
router.post('/:caseId/analyze', authenticate, async (req, res) => {
  try {
    console.log('🤖 Analyzing case with full context:', req.params.caseId);
    const userId = req.user.uid;
    const { caseId } = req.params;
    const { analyzeFullContext = true } = req.body;

    const caseDoc = await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .get();

    if (!caseDoc.exists) {
      return res.status(404).json({ 
        success: false, 
        message: 'Case not found' 
      });
    }

    if (caseDoc.data().uid !== userId) {
      return res.status(403).json({ 
        success: false, 
        message: 'Access denied' 
      });
    }

    const caseData = caseDoc.data();
    
    const comprehensivePrompt = `
You are a medical assistant helping paramedics and nurses in emergency situations.

PATIENT INFORMATION:
- Name: ${caseData.patientFirstName} ${caseData.patientLastName}
- Date of Birth: ${caseData.patientDob || 'Not provided'}
- Smoker: ${caseData.isSmoker === true ? 'Yes' : caseData.isSmoker === false ? 'No' : 'Not specified'}
- Chest Pain: ${caseData.hasChestPain === true ? 'Yes' : caseData.hasChestPain === false ? 'No' : 'Not specified'}
- Family History of Heart Problems: ${caseData.hasFamilyHistory === true ? 'Yes' : caseData.hasFamilyHistory === false ? 'No' : 'Not specified'}

ADDITIONAL NOTES FROM PARAMEDIC:
${caseData.additionalNotes || 'No additional notes provided'}

ECG DATA/CONTENT:
${caseData.ecgContent || 'No ECG data extracted'}

Based on ALL the above information, provide a comprehensive medical analysis including:

1. **Immediate Assessment** - Critical findings from the ECG and patient presentation
2. **Differential Diagnosis** - Possible conditions to consider
3. **Emergency Treatment Plan** - Step-by-step instructions for paramedics (use Markdown formatting with bold steps)
4. **Monitoring Recommendations** - What to watch for during transport
5. **Hospital Preparation** - What the receiving hospital should know

Respond in English only with clear, structured medical guidance.
`;

    console.log('🤖 Sending comprehensive data to AI...');
    
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
            content: "You are an expert medical assistant for emergency responders. Provide clear, actionable medical guidance based on all available patient data."
          },
          { role: "user", content: comprehensivePrompt },
        ],
        temperature: 0.7,
      }),
    });

    const openaiData = await openaiResponse.json();
    
    if (!openaiData.choices || !openaiData.choices[0]) {
      throw new Error('Invalid response from OpenAI API');
    }
    
    const comprehensiveAnalysis = openaiData.choices[0].message.content.trim();

    await admin.firestore()
      .collection('cases')
      .doc(caseId)
      .update({
        conditionNameEn: 'Comprehensive Analysis Complete',
        analysisResults: comprehensiveAnalysis,
        botDiagnosis: comprehensiveAnalysis,
        status: 'analyzed',
        analyzedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log('✅ Comprehensive analysis completed and saved');

    res.json({
      success: true,
      message: 'Case analyzed successfully',
      analysis: comprehensiveAnalysis
    });

  } catch (error) {
    console.error('❌ Case analysis error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error analyzing case: ' + error.message 
    });
  }
});

module.exports = router;