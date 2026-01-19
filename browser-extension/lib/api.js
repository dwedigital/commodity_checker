// Tariffik API client for browser extension

// Environment configuration
// Change this to switch between environments:
// - 'local': http://localhost:3000 (for development)
// - 'staging': https://tariffik-staging.onrender.com
// - 'production': https://tariffik.com
const ENVIRONMENT = 'production';

const HOSTS = {
  local: 'http://localhost:3000',
  staging: 'https://tariffik-staging.onrender.com',
  production: 'https://tariffik.com'
};

// Base URL for the website (for links)
const SITE_BASE_URL = HOSTS[ENVIRONMENT];

// Base URL for API calls
const API_BASE_URL = `${SITE_BASE_URL}/api/v1/extension`;

// Get extension ID for anonymous lookups
async function getExtensionId() {
  const result = await chrome.storage.local.get('extensionId');
  if (result.extensionId) {
    return result.extensionId;
  }

  // Generate a new extension ID
  const extensionId = 'ext_' + crypto.randomUUID();
  await chrome.storage.local.set({ extensionId });
  return extensionId;
}

// Get stored auth token
async function getAuthToken() {
  const result = await chrome.storage.local.get('authToken');
  return result.authToken || null;
}

// Store auth token
async function setAuthToken(token) {
  await chrome.storage.local.set({ authToken: token });
}

// Clear auth token
async function clearAuthToken() {
  await chrome.storage.local.remove('authToken');
}

// Get user info
async function getUserInfo() {
  const result = await chrome.storage.local.get('userInfo');
  return result.userInfo || null;
}

// Store user info
async function setUserInfo(info) {
  await chrome.storage.local.set({ userInfo: info });
}

// Clear user info
async function clearUserInfo() {
  await chrome.storage.local.remove('userInfo');
}

// Check if user is authenticated
async function isAuthenticated() {
  const token = await getAuthToken();
  return !!token;
}

// Make API request
async function apiRequest(endpoint, options = {}) {
  const url = `${API_BASE_URL}${endpoint}`;
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...options.headers
  };

  // Add auth token if available
  const token = await getAuthToken();
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  let response;
  try {
    response = await fetch(url, {
      ...options,
      headers
    });
  } catch (error) {
    // Network error (server not running, CORS, etc.)
    throw new Error(`Cannot connect to server. Make sure the server is running at ${API_BASE_URL.replace('/api/v1/extension', '')}`);
  }

  // Try to parse JSON, handle HTML responses gracefully
  let data;
  const contentType = response.headers.get('content-type') || '';

  if (contentType.includes('application/json')) {
    try {
      data = await response.json();
    } catch (e) {
      throw new Error('Invalid JSON response from server');
    }
  } else {
    // Server returned HTML (likely an error page or 404)
    const text = await response.text();
    if (text.includes('<!doctype') || text.includes('<html')) {
      throw new Error(`API endpoint not found. Server returned HTML instead of JSON. Status: ${response.status}`);
    }
    throw new Error(`Unexpected response format: ${text.substring(0, 100)}`);
  }

  // Handle token revocation
  if (response.status === 401 && token) {
    await clearAuthToken();
    await clearUserInfo();
  }

  return { response, data };
}

// Check usage for anonymous extension
async function checkUsage() {
  const extensionId = await getExtensionId();
  const { response, data } = await apiRequest(`/usage?extension_id=${encodeURIComponent(extensionId)}`);

  if (!response.ok) {
    throw new Error(data.message || 'Failed to check usage');
  }

  return data;
}

// Perform commodity code lookup
async function lookup({ url, description, product, saveToAccount = true }) {
  const token = await getAuthToken();
  const extensionId = await getExtensionId();

  const body = {
    url,
    description,
    product,
    save_to_account: saveToAccount
  };

  // Add extension_id for anonymous requests
  if (!token) {
    body.extension_id = extensionId;
  }

  const { response, data } = await apiRequest('/lookup', {
    method: 'POST',
    body: JSON.stringify(body)
  });

  return { response, data };
}

// Exchange auth code for token
async function exchangeToken(code) {
  const extensionId = await getExtensionId();

  const { response, data } = await apiRequest('/token', {
    method: 'POST',
    body: JSON.stringify({
      code,
      extension_id: extensionId
    })
  });

  if (!response.ok) {
    throw new Error(data.message || 'Failed to exchange token');
  }

  // Store the token and user info
  await setAuthToken(data.token);
  await setUserInfo(data.user);

  return data;
}

// Revoke current token (sign out)
async function revokeToken() {
  const { response, data } = await apiRequest('/token', {
    method: 'DELETE'
  });

  // Clear local storage regardless of response
  await clearAuthToken();
  await clearUserInfo();

  return { response, data };
}

// Get auth URL for OAuth flow
async function getAuthUrl() {
  const extensionId = await getExtensionId(); // Use same ID as token exchange
  const callbackUrl = chrome.runtime.getURL('callback/callback.html');
  const baseUrl = API_BASE_URL.replace('/api/v1/extension', '');

  return `${baseUrl}/extension/auth?extension_id=${encodeURIComponent(extensionId)}&redirect_uri=${encodeURIComponent(callbackUrl)}`;
}

export {
  getExtensionId,
  getAuthToken,
  setAuthToken,
  clearAuthToken,
  getUserInfo,
  setUserInfo,
  clearUserInfo,
  isAuthenticated,
  checkUsage,
  lookup,
  exchangeToken,
  revokeToken,
  getAuthUrl,
  API_BASE_URL,
  SITE_BASE_URL
};
