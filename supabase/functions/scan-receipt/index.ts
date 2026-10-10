// Supabase Edge Function for receipt scanning using Google Cloud Vision API
// Extracts amount, date, and merchant information from receipt images

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { extractAmount, isAmountOnlyLine } from "./amount_parser.ts";

const GOOGLE_VISION_API_URL = "https://vision.googleapis.com/v1/images:annotate";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

interface ScanResult {
  amount: number | null;
  date: string | null;
  merchant: string | null;
  confidence: number;
  rawText: string;
}

interface ErrorResponse {
  error: string;
  code: string;
}

// Italian date patterns
const datePatterns = [
  // DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY
  /(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})/,
  // DD/MM/YY
  /(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2})/,
  // DD MMM YYYY (e.g., 15 DIC 2024)
  /(\d{1,2})\s+(GEN|FEB|MAR|APR|MAG|GIU|LUG|AGO|SET|OTT|NOV|DIC)\w*\s+(\d{4})/i,
];

// Italian month abbreviations
const monthMap: Record<string, string> = {
  'GEN': '01', 'GENNAIO': '01',
  'FEB': '02', 'FEBBRAIO': '02',
  'MAR': '03', 'MARZO': '03',
  'APR': '04', 'APRILE': '04',
  'MAG': '05', 'MAGGIO': '05',
  'GIU': '06', 'GIUGNO': '06',
  'LUG': '07', 'LUGLIO': '07',
  'AGO': '08', 'AGOSTO': '08',
  'SET': '09', 'SETTEMBRE': '09',
  'OTT': '10', 'OTTOBRE': '10',
  'NOV': '11', 'NOVEMBRE': '11',
  'DIC': '12', 'DICEMBRE': '12',
};

function extractDate(text: string): string | null {
  for (const pattern of datePatterns) {
    const match = text.match(pattern);
    if (match) {
      let day: string, month: string, year: string;

      if (pattern.source.includes('GEN|FEB')) {
        // Italian month name format
        day = match[1].padStart(2, '0');
        const monthStr = match[2].toUpperCase().substring(0, 3);
        month = monthMap[monthStr] || '01';
        year = match[3];
      } else {
        day = match[1].padStart(2, '0');
        month = match[2].padStart(2, '0');
        year = match[3].length === 2 ? '20' + match[3] : match[3];
      }

      // Validate date
      const dateStr = `${year}-${month}-${day}`;
      const parsedDate = new Date(dateStr);
      if (!isNaN(parsedDate.getTime())) {
        return dateStr;
      }
    }
  }
  return null;
}

function extractMerchant(text: string): string | null {
  // Split into lines and look for merchant name
  const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0);

  // Common patterns to skip
  const skipPatterns = [
    /^(SCONTRINO|RICEVUTA|DOCUMENTO|FISCALE)/i,
    /^(P\.IVA|P\.I\.|C\.F\.|REG\.)/i,
    /^(DATA|ORA|CASSA)/i,
    /^(TOTALE|TOT|SUBTOT|RESTO)/i,
    /^[\d\/\-\.]+$/,
  ];

  // First few non-skipped lines are likely the merchant name
  for (const line of lines.slice(0, 5)) {
    const shouldSkip = isAmountOnlyLine(line) || skipPatterns.some(p => p.test(line));
    if (!shouldSkip && line.length >= 3 && line.length <= 50) {
      // Clean up the merchant name
      const cleaned = line
        .replace(/[^\w\s\-\'àèéìòù]/gi, '')
        .trim();
      if (cleaned.length >= 3) {
        return cleaned;
      }
    }
  }

  return null;
}

function calculateConfidence(result: ScanResult): number {
  let score = 0;
  let factors = 0;

  if (result.amount !== null) {
    score += 40;
    factors++;
  }
  if (result.date !== null) {
    score += 30;
    factors++;
  }
  if (result.merchant !== null) {
    score += 30;
    factors++;
  }

  // Bonus for having all fields
  if (factors === 3) {
    score += 10;
  }

  return Math.min(score, 100);
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  // Use Deno's native base64 decoder
  const decoder = new TextDecoder('utf-8');

  // Decode using standard base64
  try {
    // Method 1: Try atob first
    const binaryString = atob(base64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
  } catch (e) {
    // Method 2: Fallback - manual base64 decode
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    let i = 0;

    base64 = base64.replace(/[^A-Za-z0-9\+\/\=]/g, '');

    while (i < base64.length) {
      const enc1 = chars.indexOf(base64.charAt(i++));
      const enc2 = chars.indexOf(base64.charAt(i++));
      const enc3 = chars.indexOf(base64.charAt(i++));
      const enc4 = chars.indexOf(base64.charAt(i++));

      const chr1 = (enc1 << 2) | (enc2 >> 4);
      const chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
      const chr3 = ((enc3 & 3) << 6) | enc4;

      output = output + String.fromCharCode(chr1);

      if (enc3 !== 64) {
        output = output + String.fromCharCode(chr2);
      }
      if (enc4 !== 64) {
        output = output + String.fromCharCode(chr3);
      }
    }

    const bytes = new Uint8Array(output.length);
    for (let i = 0; i < output.length; i++) {
      bytes[i] = output.charCodeAt(i);
    }
    return bytes.buffer;
  }
}

async function getAccessToken(serviceAccountJson: string): Promise<string> {
  try {
    console.log('Raw secret first 200 chars:', serviceAccountJson.substring(0, 200));
    console.log('Raw secret last 100 chars:', serviceAccountJson.substring(serviceAccountJson.length - 100));

    const serviceAccount = JSON.parse(serviceAccountJson);

    // Normalize private key - ensure proper newlines
    let privateKeyPem = serviceAccount.private_key;

    console.log('Private key type:', typeof privateKeyPem);
    console.log('Private key length:', privateKeyPem?.length);
    console.log('Private key starts with:', privateKeyPem?.substring(0, 80));
    console.log('Private key ends with:', privateKeyPem?.substring(privateKeyPem.length - 80));

    // Check for common issues
    console.log('Contains \\n:', privateKeyPem.includes('\\n'));
    console.log('Contains actual newline:', privateKeyPem.includes('\n'));
    console.log('Contains double backslash:', privateKeyPem.includes('\\\\'));

    // Use regex to find header and footer (handles any spacing variations)
    const headerRegex = /-----BEGIN\s+PRIVATE\s+KEY-----/;
    const footerRegex = /-----END\s+PRIVATE\s+KEY-----/;

    const headerMatch = privateKeyPem.match(headerRegex);
    const footerMatch = privateKeyPem.match(footerRegex);

    if (!headerMatch) {
      throw new Error('Invalid PEM format: missing header');
    }

    if (!footerMatch) {
      throw new Error('Invalid PEM format: missing footer');
    }

    const headerIndex = headerMatch.index!;
    const footerIndex = footerMatch.index!;

    // Extract everything between header and footer, then remove ALL whitespace
    const startIndex = headerIndex + headerMatch[0].length;
    const pemContents = privateKeyPem
      .substring(startIndex, footerIndex)
      .replace(/\s/g, '')  // Remove ALL whitespace
      .trim();

    console.log('PEM contents length:', pemContents.length);
    console.log('PEM contents first 50 chars:', pemContents.substring(0, 50));

    // Convert to ArrayBuffer
    const binaryDer = base64ToArrayBuffer(pemContents);

    // Import the key
    const cryptoKey = await crypto.subtle.importKey(
      'pkcs8',
      binaryDer,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign']
    );

    // Create JWT claims
    const payload = {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/cloud-vision",
      aud: GOOGLE_TOKEN_URL,
      exp: getNumericDate(3600), // 1 hour
      iat: getNumericDate(0),
    };

    // Create signed JWT with CryptoKey
    const jwt = await create({ alg: "RS256", typ: "JWT" }, payload, cryptoKey);

    // Exchange JWT for access token
    const response = await fetch(GOOGLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Failed to get access token: ${error}`);
    }

    const data = await response.json();
    return data.access_token;
  } catch (error) {
    throw new Error(`Service account authentication failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

async function callGoogleVisionAPI(imageBase64: string, accessToken: string): Promise<string> {
  const requestBody = {
    requests: [
      {
        image: {
          content: imageBase64,
        },
        features: [
          {
            type: "TEXT_DETECTION",
            maxResults: 1,
          },
        ],
        imageContext: {
          languageHints: ["it"],
        },
      },
    ],
  };

  const response = await fetch(GOOGLE_VISION_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Google Vision API error: ${error}`);
  }

  const data = await response.json();
  const textAnnotations = data.responses?.[0]?.textAnnotations;

  if (!textAnnotations || textAnnotations.length === 0) {
    throw new Error("No text detected in image");
  }

  return textAnnotations[0].description || "";
}

serve(async (req: Request) => {
  // CORS headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get Google Service Account JSON from environment
    const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
    if (!serviceAccountJson) {
      return new Response(
        JSON.stringify({ error: "Google Service Account not configured", code: "config_error" } as ErrorResponse),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse request body
    const { image } = await req.json();

    if (!image) {
      return new Response(
        JSON.stringify({ error: "No image provided", code: "invalid_request" } as ErrorResponse),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Remove data URL prefix if present
    const base64Image = image.replace(/^data:image\/\w+;base64,/, "");

    // Get access token from service account
    const accessToken = await getAccessToken(serviceAccountJson);

    // Call Google Vision API
    const extractedText = await callGoogleVisionAPI(base64Image, accessToken);

    // Parse the extracted text
    const result: ScanResult = {
      amount: extractAmount(extractedText),
      date: extractDate(extractedText),
      merchant: extractMerchant(extractedText),
      confidence: 0,
      rawText: extractedText,
    };

    // Calculate confidence score
    result.confidence = calculateConfidence(result);

    return new Response(
      JSON.stringify(result),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error processing receipt:", error);

    const errorMessage = error instanceof Error ? error.message : "Unknown error";

    return new Response(
      JSON.stringify({
        error: `Failed to process receipt: ${errorMessage}`,
        code: "processing_error"
      } as ErrorResponse),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
