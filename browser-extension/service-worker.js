// Tariffik Browser Extension - Service Worker
// Handles background tasks, message passing, and OAuth callback

import * as api from './lib/api.js';

// Handle messages from popup and content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse);
  return true; // Keep channel open for async response
});

async function handleMessage(message, sender) {
  switch (message.type) {
    case 'GET_PRODUCT_INFO':
      return getProductInfoFromTab(sender.tab?.id);

    case 'LOOKUP':
      return performLookup(message.data);

    case 'CHECK_USAGE':
      return checkUsage();

    case 'GET_AUTH_STATUS':
      return getAuthStatus();

    case 'SIGN_OUT':
      return signOut();

    case 'EXCHANGE_TOKEN':
      return exchangeToken(message.code);

    default:
      return { error: 'Unknown message type' };
  }
}

// Get product info from the current tab's content script
async function getProductInfoFromTab(tabId) {
  if (!tabId) {
    return { error: 'No tab ID provided' };
  }

  try {
    const response = await chrome.tabs.sendMessage(tabId, { type: 'EXTRACT_PRODUCT' });
    return response;
  } catch (error) {
    console.error('Error getting product info:', error);
    return { error: 'Could not extract product information from this page' };
  }
}

// Perform commodity code lookup
async function performLookup(data) {
  try {
    const { response, data: result } = await api.lookup(data);

    if (!response.ok) {
      return {
        error: true,
        status: response.status,
        ...result
      };
    }

    return {
      success: true,
      ...result
    };
  } catch (error) {
    console.error('Lookup error:', error);
    return {
      error: true,
      message: error.message || 'Failed to perform lookup'
    };
  }
}

// Check usage statistics
async function checkUsage() {
  try {
    const isAuth = await api.isAuthenticated();

    if (isAuth) {
      // For authenticated users, get user info from storage
      const userInfo = await api.getUserInfo();
      return {
        authenticated: true,
        user: userInfo
      };
    } else {
      // For anonymous users, check API usage
      const usage = await api.checkUsage();
      return {
        authenticated: false,
        usage
      };
    }
  } catch (error) {
    console.error('Usage check error:', error);
    return {
      error: true,
      message: error.message || 'Failed to check usage'
    };
  }
}

// Get authentication status
async function getAuthStatus() {
  const isAuth = await api.isAuthenticated();
  const userInfo = isAuth ? await api.getUserInfo() : null;
  const authUrl = await api.getAuthUrl();

  return {
    authenticated: isAuth,
    user: userInfo,
    authUrl: authUrl
  };
}

// Sign out
async function signOut() {
  try {
    await api.revokeToken();
    return { success: true };
  } catch (error) {
    console.error('Sign out error:', error);
    // Still consider it successful as we cleared local data
    return { success: true };
  }
}

// Exchange OAuth code for token
async function exchangeToken(code) {
  try {
    const result = await api.exchangeToken(code);
    return {
      success: true,
      user: result.user
    };
  } catch (error) {
    console.error('Token exchange error:', error);
    return {
      error: true,
      message: error.message || 'Failed to complete sign in'
    };
  }
}

// Configure side panel behavior - open when action icon is clicked
chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true })
  .catch((error) => console.error('Failed to set side panel behavior:', error));

// Listen for extension installation/update
chrome.runtime.onInstalled.addListener(async (details) => {
  if (details.reason === 'install') {
    // Generate extension ID on first install
    await api.getExtensionId();
    console.log('Tariffik extension installed');
  }
});
