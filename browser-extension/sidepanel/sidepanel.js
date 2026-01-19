// Tariffik Browser Extension - Side Panel Script

import { SITE_BASE_URL } from '../lib/api.js';

// UI Elements
const elements = {
  loading: document.getElementById('loading'),
  productSection: document.getElementById('productSection'),
  productInfo: document.getElementById('productInfo'),
  clearProductLink: document.getElementById('clearProductLink'),
  manualSection: document.getElementById('manualSection'),
  descriptionInput: document.getElementById('descriptionInput'),
  lookupSection: document.getElementById('lookupSection'),
  lookupBtn: document.getElementById('lookupBtn'),
  usageInfo: document.getElementById('usageInfo'),
  resultSection: document.getElementById('resultSection'),
  result: document.getElementById('result'),
  errorSection: document.getElementById('errorSection'),
  errorMessage: document.getElementById('errorMessage'),
  noLookupsSection: document.getElementById('noLookupsSection'),
  signInSection: document.getElementById('signInSection'),
  signInBtn: document.getElementById('signInBtn'),
  userStatus: document.getElementById('userStatus'),
  signOutLink: document.getElementById('signOutLink'),
  historySection: document.getElementById('historySection'),
  historyList: document.getElementById('historyList'),
  clearHistoryLink: document.getElementById('clearHistoryLink'),
  signUpLink: document.getElementById('signUpLink'),
  footerLink: document.getElementById('footerLink')
};

// Set dynamic URLs based on environment
elements.signUpLink.href = `${SITE_BASE_URL}/users/sign_up`;
elements.footerLink.href = SITE_BASE_URL;

// State
let currentProduct = null;
let authStatus = null;
let lookupHistory = [];
let isLookupInProgress = false;  // Lock to prevent UI updates during lookup
let hasActiveResult = false;      // Track if we're showing a result

// Initialize side panel
async function init() {
  try {
    // Reset UI state
    elements.resultSection.classList.add('hidden');
    elements.errorSection.classList.add('hidden');
    elements.noLookupsSection.classList.add('hidden');

    // Get auth status
    authStatus = await chrome.runtime.sendMessage({ type: 'GET_AUTH_STATUS' });
    updateAuthUI();

    // Check usage
    let usageData = { error: false };
    try {
      usageData = await chrome.runtime.sendMessage({ type: 'CHECK_USAGE' });
      updateUsageUI(usageData);
    } catch (e) {
      console.error('Usage check failed:', e);
      // Continue anyway - we'll show the lookup button
    }

    // Get current tab info
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

    // Try to extract product info from the page
    if (tab?.id) {
      try {
        currentProduct = await chrome.tabs.sendMessage(tab.id, { type: 'EXTRACT_PRODUCT' });
        if (currentProduct && (currentProduct.title || currentProduct.url)) {
          showProductInfo(currentProduct);
        } else {
          showManualInput();
        }
      } catch (e) {
        // Content script not available on this page
        showManualInput();
      }
    } else {
      showManualInput();
    }

    // Show lookup section - always show unless we know for certain lookups are exhausted
    if (usageData.error || hasLookupsRemaining(usageData)) {
      elements.lookupSection.classList.remove('hidden');
    } else {
      // No lookups remaining
      elements.noLookupsSection.classList.remove('hidden');
    }

    // Show sign-in section if not authenticated (to encourage sign up)
    if (!authStatus?.authenticated) {
      elements.signInSection.classList.remove('hidden');
    } else {
      elements.signInSection.classList.add('hidden');
    }

    // Load local lookup history
    await loadHistory();

    // Hide loading
    elements.loading.classList.add('hidden');

  } catch (error) {
    console.error('Init error:', error);
    showError('Failed to initialize. Please try again.');
    elements.loading.classList.add('hidden');
    // Still show lookup section so user can try
    elements.lookupSection.classList.remove('hidden');
  }
}

// Update auth UI
function updateAuthUI() {
  if (authStatus?.authenticated) {
    const user = authStatus.user;
    elements.userStatus.innerHTML = `
      <span class="tier">${user?.subscription_tier || 'free'}</span>
    `;
    elements.signOutLink.classList.remove('hidden');
  } else {
    elements.userStatus.textContent = '';
    elements.signOutLink.classList.add('hidden');
  }
}

// Update usage UI
function updateUsageUI(data) {
  if (data.error) {
    elements.usageInfo.textContent = '';
    return;
  }

  if (data.authenticated) {
    const user = data.user;
    if (user?.lookups_remaining === null) {
      elements.usageInfo.textContent = 'Unlimited lookups';
    } else {
      elements.usageInfo.textContent = `${user?.lookups_remaining || 0} lookups remaining this month`;
    }
  } else {
    const usage = data.usage;
    elements.usageInfo.textContent = `${usage?.remaining || 0} of ${usage?.limit || 3} free lookups remaining`;

    // Show no lookups section if none remaining
    if (usage?.remaining === 0) {
      elements.lookupSection.classList.add('hidden');
      elements.noLookupsSection.classList.remove('hidden');

      // Show sign in option if not authenticated
      if (!authStatus?.authenticated) {
        elements.signInSection.classList.remove('hidden');
      }
    }
  }
}

// Check if user has lookups remaining
function hasLookupsRemaining(data) {
  if (data.authenticated) {
    return data.user?.lookups_remaining === null || data.user?.lookups_remaining > 0;
  }
  return data.usage?.remaining > 0;
}

// Show product info
function showProductInfo(product) {
  const title = product.title || 'Product detected';
  const url = new URL(product.url || window.location.href);
  const hostname = url.hostname.replace('www.', '');

  let meta = [];
  if (product.brand) meta.push(`Brand: ${product.brand}`);
  if (product.price) meta.push(`Price: ${product.price}`);

  elements.productInfo.innerHTML = `
    <div class="title">${escapeHtml(title)}</div>
    <div class="url">${escapeHtml(hostname)}</div>
    ${meta.length ? `<div class="meta">${meta.map(m => escapeHtml(m)).join(' | ')}</div>` : ''}
  `;

  elements.productSection.classList.remove('hidden');
  elements.manualSection.classList.add('hidden');
}

// Show manual input
function showManualInput() {
  elements.manualSection.classList.remove('hidden');
  elements.productSection.classList.add('hidden');
}

// Clear detected product and switch to manual input
function clearDetectedProduct() {
  currentProduct = null;
  showManualInput();
}

// Load lookup history from local storage
async function loadHistory() {
  try {
    const result = await chrome.storage.local.get('lookupHistory');
    lookupHistory = result.lookupHistory || [];
    displayHistory();
  } catch (error) {
    console.error('Failed to load history:', error);
  }
}

// Display lookup history
function displayHistory() {
  if (lookupHistory.length === 0) {
    elements.historySection.classList.add('hidden');
    return;
  }

  elements.historySection.classList.remove('hidden');
  elements.historyList.innerHTML = lookupHistory
    .slice(0, 5) // Show only last 5 lookups
    .map(item => `
      <div class="history-item" data-code="${escapeHtml(item.code)}">
        <div class="title">${escapeHtml(item.title || 'Product lookup')}</div>
        <div class="code">${escapeHtml(item.code)}</div>
      </div>
    `)
    .join('');

  // Add click handlers to history items
  elements.historyList.querySelectorAll('.history-item').forEach(item => {
    item.addEventListener('click', () => {
      const code = item.dataset.code;
      if (code) {
        navigator.clipboard.writeText(code).catch(console.error);
        item.querySelector('.code').textContent = 'Copied!';
        setTimeout(() => {
          item.querySelector('.code').textContent = code;
        }, 1500);
      }
    });
  });
}

// Save lookup to history
async function saveToHistory(title, code) {
  try {
    const result = await chrome.storage.local.get('lookupHistory');
    const history = result.lookupHistory || [];

    // Add new item at the beginning
    history.unshift({
      title: title || 'Product lookup',
      code: code,
      timestamp: Date.now()
    });

    // Keep only last 20 items
    const trimmedHistory = history.slice(0, 20);

    await chrome.storage.local.set({ lookupHistory: trimmedHistory });
    lookupHistory = trimmedHistory;
    displayHistory();
  } catch (error) {
    console.error('Failed to save to history:', error);
  }
}

// Clear all lookup history
async function clearHistory() {
  try {
    await chrome.storage.local.remove('lookupHistory');
    lookupHistory = [];
    displayHistory();
  } catch (error) {
    console.error('Failed to clear history:', error);
  }
}

// Progress messages for URL-based lookups
const PROGRESS_MESSAGES = [
  { delay: 0, message: 'Fetching product page...' },
  { delay: 3000, message: 'Analyzing page content...' },
  { delay: 6000, message: 'Trying enhanced fetch methods...' },
  { delay: 10000, message: 'Using advanced techniques...' },
  { delay: 15000, message: 'Almost there, please wait...' }
];

// Update button text with progress message
function updateProgressMessage(message) {
  const btnText = elements.lookupBtn.querySelector('.btn-text');
  if (btnText) {
    btnText.textContent = message;
  }
}

// Start progress message rotation
function startProgressMessages(isUrlLookup) {
  const timers = [];

  if (isUrlLookup) {
    // For URL lookups, show progressive messages
    PROGRESS_MESSAGES.forEach(({ delay, message }) => {
      const timer = setTimeout(() => updateProgressMessage(message), delay);
      timers.push(timer);
    });
  } else {
    // For description lookups, just show analyzing
    updateProgressMessage('Analyzing description...');
  }

  return timers;
}

// Clear progress timers
function clearProgressTimers(timers) {
  timers.forEach(timer => clearTimeout(timer));
}

// Perform lookup
async function performLookup() {
  // Lock to prevent navigation from updating product info during lookup
  isLookupInProgress = true;
  hasActiveResult = false;

  // Show loading state on button
  elements.lookupBtn.disabled = true;
  elements.lookupBtn.querySelector('.btn-text').textContent = 'Starting lookup...';
  elements.lookupBtn.querySelector('.btn-spinner').classList.remove('hidden');

  // Hide previous results/errors
  elements.resultSection.classList.add('hidden');
  elements.errorSection.classList.add('hidden');

  let progressTimers = [];

  try {
    const lookupData = {};
    let isUrlLookup = false;

    // Use product URL if available, otherwise use description
    if (currentProduct?.url) {
      lookupData.url = currentProduct.url;
      isUrlLookup = true;
      if (currentProduct.title) {
        lookupData.product = {
          title: currentProduct.title,
          description: currentProduct.description,
          brand: currentProduct.brand
        };
      }
    } else {
      const description = elements.descriptionInput.value.trim();
      if (!description) {
        throw new Error('Please enter a product description');
      }
      lookupData.description = description;
    }

    // Start progress message rotation
    progressTimers = startProgressMessages(isUrlLookup);

    // Perform lookup via service worker
    const result = await chrome.runtime.sendMessage({
      type: 'LOOKUP',
      data: lookupData
    });

    // Clear progress timers
    clearProgressTimers(progressTimers);

    if (result.error) {
      if (result.status === 402) {
        // Payment required - out of lookups
        elements.lookupSection.classList.add('hidden');
        elements.noLookupsSection.classList.remove('hidden');
        if (!authStatus?.authenticated) {
          elements.signInSection.classList.remove('hidden');
        }
      } else {
        showError(result.message || 'Failed to look up commodity code');
      }
    } else {
      showResult(result);
      hasActiveResult = true;  // Mark that we have an active result

      // Save to local history
      const title = currentProduct?.title || elements.descriptionInput.value.trim();
      if (result.commodity_code) {
        await saveToHistory(title, result.commodity_code);
      }

      // Refresh usage info
      const usageData = await chrome.runtime.sendMessage({ type: 'CHECK_USAGE' });
      updateUsageUI(usageData);
    }
  } catch (error) {
    clearProgressTimers(progressTimers);
    showError(error.message || 'An unexpected error occurred');
  } finally {
    // Unlock - allow navigation updates again
    isLookupInProgress = false;

    // Reset button state
    elements.lookupBtn.disabled = false;
    elements.lookupBtn.querySelector('.btn-text').textContent = 'Look Up Commodity Code';
    elements.lookupBtn.querySelector('.btn-spinner').classList.add('hidden');
  }
}

// Format fetch method for display
function formatFetchMethod(method) {
  const methodLabels = {
    'direct': 'Direct fetch',
    'premium_proxy': 'Enhanced proxy',
    'stealth_proxy': 'Advanced stealth mode'
  };
  return methodLabels[method] || method;
}

// Show result
function showResult(result) {
  const confidence = result.confidence || 0;
  const confidenceClass = confidence >= 0.8 ? 'high' : confidence >= 0.5 ? 'medium' : 'low';
  const confidenceText = confidence >= 0.8 ? 'High confidence' : confidence >= 0.5 ? 'Medium confidence' : 'Low confidence';
  const commodityCode = result.commodity_code || 'N/A';

  // Build fetch method info if available
  let fetchInfo = '';
  const scrapedProduct = result.scraped_product;
  if (scrapedProduct?.fetched_via) {
    fetchInfo = `<div class="fetch-info">Fetched via: ${escapeHtml(formatFetchMethod(scrapedProduct.fetched_via))}</div>`;
  }

  elements.result.innerHTML = `
    <div class="code">${escapeHtml(commodityCode)}</div>
    <div class="confidence ${confidenceClass}">${confidenceText} (${Math.round(confidence * 100)}%)</div>
    <div class="reasoning">${escapeHtml(result.reasoning || 'No additional details available')}</div>
    ${result.category ? `<div class="category">Category: ${escapeHtml(result.category)}</div>` : ''}
    ${fetchInfo}
    <div class="actions">
      <button class="btn btn-secondary" id="copyCodeBtn">Copy Code</button>
      <a href="${SITE_BASE_URL}/dashboard/product_lookups" target="_blank" class="btn btn-secondary">View History</a>
    </div>
  `;

  // Add click handler for copy button (CSP doesn't allow inline onclick)
  document.getElementById('copyCodeBtn').addEventListener('click', () => {
    copyCode(commodityCode);
  });

  elements.resultSection.classList.remove('hidden');
}

// Copy code to clipboard
async function copyCode(code) {
  try {
    await navigator.clipboard.writeText(code);
    // Show brief feedback
    const btn = document.getElementById('copyCodeBtn');
    if (btn) {
      const originalText = btn.textContent;
      btn.textContent = 'Copied!';
      setTimeout(() => { btn.textContent = originalText; }, 1500);
    }
  } catch (e) {
    console.error('Failed to copy:', e);
  }
}

// Show error
function showError(message) {
  elements.errorMessage.textContent = message;
  elements.errorSection.classList.remove('hidden');
}

// Sign in
async function signIn() {
  if (authStatus?.authUrl) {
    // Open auth URL in new tab - side panel stays open
    chrome.tabs.create({ url: authStatus.authUrl });
  }
}

// Sign out
async function signOut() {
  await chrome.runtime.sendMessage({ type: 'SIGN_OUT' });
  // Refresh the popup
  window.location.reload();
}

// Escape HTML
function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Event listeners
elements.lookupBtn.addEventListener('click', performLookup);
elements.signInBtn.addEventListener('click', signIn);
elements.signOutLink.addEventListener('click', (e) => {
  e.preventDefault();
  signOut();
});
elements.clearHistoryLink.addEventListener('click', (e) => {
  e.preventDefault();
  clearHistory();
});
elements.clearProductLink.addEventListener('click', (e) => {
  e.preventDefault();
  clearDetectedProduct();
});

// Allow Enter key in textarea to trigger lookup
elements.descriptionInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    performLookup();
  }
});

// Listen for auth completion messages from callback page
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'AUTH_COMPLETE') {
    // Re-initialize the side panel to show authenticated state
    init();
    sendResponse({ received: true });
  }
  return true;
});

// Track current URL to detect navigation
let currentTabUrl = null;

// Listen for tab switches
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  await refreshProductInfo();
});

// Listen for URL changes within the same tab (page navigation)
chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  // Only refresh when the page has finished loading and URL changed
  if (changeInfo.status === 'complete' && tab.active) {
    // Check if URL changed
    if (tab.url !== currentTabUrl) {
      currentTabUrl = tab.url;
      await refreshProductInfo();
    }
  }
});

// Refresh product info from current tab
async function refreshProductInfo() {
  // If lookup is in progress, don't update anything - keep product info locked
  if (isLookupInProgress) {
    return;
  }

  try {
    // If there was an active result, clear it since we navigated away
    if (hasActiveResult) {
      hasActiveResult = false;
      elements.resultSection.classList.add('hidden');
    }

    // Show loading state briefly
    elements.loading.classList.remove('hidden');
    elements.productSection.classList.add('hidden');
    elements.manualSection.classList.add('hidden');
    elements.errorSection.classList.add('hidden');

    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    currentTabUrl = tab?.url;

    if (tab?.id) {
      // Small delay to ensure content script is ready after navigation
      await new Promise(resolve => setTimeout(resolve, 300));

      try {
        currentProduct = await chrome.tabs.sendMessage(tab.id, { type: 'EXTRACT_PRODUCT' });
        if (currentProduct && (currentProduct.title || currentProduct.url)) {
          showProductInfo(currentProduct);
        } else {
          showManualInput();
        }
      } catch (e) {
        // Content script not available on this page
        showManualInput();
      }
    } else {
      showManualInput();
    }

    elements.loading.classList.add('hidden');
  } catch (error) {
    console.error('Error refreshing product info:', error);
    elements.loading.classList.add('hidden');
    showManualInput();
  }
}

// Initialize
init();
