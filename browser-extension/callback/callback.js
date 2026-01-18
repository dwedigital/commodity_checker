// Tariffik Browser Extension - OAuth Callback Handler

import { SITE_BASE_URL } from '../lib/api.js';

// Set dynamic URLs
document.getElementById('successLink').href = SITE_BASE_URL;
document.getElementById('errorLink').href = SITE_BASE_URL;

async function handleCallback() {
  const loadingEl = document.getElementById('loading');
  const successEl = document.getElementById('success');
  const errorEl = document.getElementById('error');
  const errorMessage = document.getElementById('errorMessage');

  try {
    // Get code from URL
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get('code');
    console.log('Callback received code:', code ? code.substring(0, 20) + '...' : 'none');

    if (!code) {
      throw new Error('No authorization code received');
    }

    // Exchange code for token with timeout
    console.log('Sending EXCHANGE_TOKEN message to service worker...');

    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error('Token exchange timed out after 15 seconds')), 15000);
    });

    const messagePromise = chrome.runtime.sendMessage({
      type: 'EXCHANGE_TOKEN',
      code: code
    });

    const result = await Promise.race([messagePromise, timeoutPromise]);
    console.log('Token exchange result:', result);

    if (!result) {
      throw new Error('No response from service worker');
    }

    if (result.error) {
      throw new Error(result.message || 'Failed to complete sign in');
    }

    // Notify side panel that auth is complete
    chrome.runtime.sendMessage({ type: 'AUTH_COMPLETE', user: result.user });

    // Show success
    loadingEl.style.display = 'none';
    successEl.style.display = 'block';

    // Auto-close after 3 seconds
    setTimeout(() => {
      window.close();
    }, 3000);

  } catch (error) {
    console.error('Callback error:', error);
    loadingEl.style.display = 'none';
    errorEl.style.display = 'block';
    errorMessage.textContent = error.message || 'Something went wrong during sign in. Please try again.';
  }
}

// Run on page load
handleCallback();
