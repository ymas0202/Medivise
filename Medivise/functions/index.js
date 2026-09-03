const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { OpenAI } = require('openai');

// Initialize Firebase Admin
admin.initializeApp();

// Initialize OpenAI (we'll set the API key securely later)
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || functions.config().openai.key,
});

// Secure ECG Analysis Function
exports.analyzeECG = functions.https.onCall(async (data, context) => {
  // 1. Check if user is authenticated
  if (!context.auth) {
    console.log('❌ Unauthenticated request');
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to analyze ECG');
  }

  console.log(`🔐 User ${context.auth.uid} requested ECG analysis`);

  // 2. Validate input data
  const { ecgData, sourceType, riskFactors, patientInfo } = data;
  
  if (!ecgData || typeof ecgData !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'ECG data is required');
  }

  if (ecgData.length > 10000) {
    throw new functions.https.HttpsError('invalid-argument', 'ECG data is too large');
  }

  // 3. Validate risk factors
  if (!riskFactors || typeof riskFactors !== 'object') {
    throw new functions.https.HttpsError('invalid-argument', 'Risk factors are required');
  }

  try {
    console.log('🔄 Calling OpenAI for ECG analysis...');

    // 4. Secure OpenAI call
    const diagnosis = await openai.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: "You are a medical assistant. Provide ECG analysis and treatment recommendations. Do not include personal information. Respond in English only."
        },
        {
          role: "user", 
          content: `Analyze this ECG data (format: ${sourceType}):

ECG Data: ${ecgData}

Risk Factors:
- Smoker: ${riskFactors.isSmoker ? "Yes" : "No"}
- Chest Pain: ${riskFactors.chestPain ? "Yes" : "No"} 
- Family History: ${riskFactors.familyHistory ? "Yes" : "No"}

Provide a clear diagnosis and immediate paramedic recommendations.`
        }
      ],
      max_tokens: 800,
      temperature: 0.4,
    });

    const analysisResult = diagnosis.choices[0].message.content;
    console.log('✅ OpenAI analysis completed');

    // 5. Extract vitals securely
    const vitals = await extractVitals(ecgData);

    // 6. Save to Firestore with server-side validation
    const caseData = {
      createdBy: context.auth.uid,
      ecgSource: sourceType,
      ecgAnalysis: analysisResult,
      patientFirstName: patientInfo.firstName.substring(0, 100), // Limit length
      patientLastName: patientInfo.lastName.substring(0, 100),   // Limit length
      dob: patientInfo.dob,
      isSmoker: riskFactors.isSmoker,
      chestPain: riskFactors.chestPain,
      familyHistory: riskFactors.familyHistory,
      vitals: vitals,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };

    const caseRef = await admin.firestore().collection('cases').add(caseData);
    console.log(`📁 Case saved: ${caseRef.id}`);

    // 7. Create chat document
    await admin.firestore().collection('chats').doc(caseRef.id).set({
      caseId: caseRef.id,
      createdBy: context.auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`💬 Chat created for case: ${caseRef.id}`);

    // 8. Return secure response
    return { 
      success: true,
      caseId: caseRef.id, 
      diagnosis: analysisResult,
      vitals: vitals
    };

  } catch (error) {
    console.error('❌ ECG Analysis Error:', error);
    throw new functions.https.HttpsError('internal', 'ECG analysis failed: ' + error.message);
  }
});

// Helper function to extract vitals
async function extractVitals(ecgText) {
  try {
    const response = await openai.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: "Extract ECG vitals and return as JSON. Only return: heartRate (bpm), prInterval (ms), qrsDuration (ms), qtcInterval (ms). Return empty object if no vitals found."
        },
        {
          role: "user",
          content: `Extract ECG vitals from: ${ecgText.substring(0, 2000)}`
        }
      ],
      max_tokens: 500,
      temperature: 0.3,
    });

    const vitalsText = response.choices[0].message.content;
    
    // Try to parse JSON, return empty object if it fails
    try {
      const vitals = JSON.parse(vitalsText);
      if (vitals && typeof vitals === 'object') {
        return vitals;
      }
    } catch (parseError) {
      console.log('⚠️ Could not parse vitals JSON:', parseError.message);
    }
    
    return {};
  } catch (error) {
    console.log('⚠️ Could not extract vitals:', error.message);
    return {};
  }
}