// Tariffik Browser Extension - Content Script
// Extracts product information from web pages

// Listen for messages from popup/service worker
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'EXTRACT_PRODUCT') {
    const product = extractProductInfo();
    sendResponse(product);
  }
  return true;
});

// Extract product information from the current page
function extractProductInfo() {
  const product = {
    url: window.location.href,
    title: null,
    description: null,
    brand: null,
    price: null,
    image: null,
    material: null,
    category: null
  };

  // Try multiple extraction methods in order of reliability
  extractFromJsonLd(product);
  extractFromOpenGraph(product);
  extractFromMeta(product);
  extractFromMicrodata(product);
  extractFromPage(product);

  // Clean up empty values
  Object.keys(product).forEach(key => {
    if (product[key] === null || product[key] === '') {
      delete product[key];
    }
  });

  return product;
}

// Extract from JSON-LD structured data
function extractFromJsonLd(product) {
  const scripts = document.querySelectorAll('script[type="application/ld+json"]');

  for (const script of scripts) {
    try {
      const data = JSON.parse(script.textContent);
      const items = Array.isArray(data) ? data : [data];

      for (const item of items) {
        // Handle @graph format
        const schemas = item['@graph'] || [item];

        for (const schema of schemas) {
          if (schema['@type'] === 'Product' || schema['@type']?.includes('Product')) {
            product.title = product.title || schema.name;
            product.description = product.description || schema.description;
            product.brand = product.brand || schema.brand?.name || schema.brand;
            product.image = product.image || getImageUrl(schema.image);
            product.material = product.material || schema.material;
            product.category = product.category || schema.category;

            // Extract price
            if (schema.offers) {
              const offers = Array.isArray(schema.offers) ? schema.offers[0] : schema.offers;
              product.price = product.price || offers.price || offers.lowPrice;
            }
          }
        }
      }
    } catch (e) {
      // Invalid JSON, skip
    }
  }
}

// Extract from Open Graph meta tags
function extractFromOpenGraph(product) {
  const ogTitle = document.querySelector('meta[property="og:title"]');
  const ogDescription = document.querySelector('meta[property="og:description"]');
  const ogImage = document.querySelector('meta[property="og:image"]');
  const ogPrice = document.querySelector('meta[property="product:price:amount"]');

  product.title = product.title || ogTitle?.content;
  product.description = product.description || ogDescription?.content;
  product.image = product.image || ogImage?.content;
  product.price = product.price || ogPrice?.content;
}

// Extract from standard meta tags
function extractFromMeta(product) {
  const titleMeta = document.querySelector('meta[name="title"]');
  const descMeta = document.querySelector('meta[name="description"]');

  product.title = product.title || titleMeta?.content || document.title;
  product.description = product.description || descMeta?.content;
}

// Extract from Microdata (schema.org)
function extractFromMicrodata(product) {
  const productElement = document.querySelector('[itemtype*="schema.org/Product"]');
  if (!productElement) return;

  const name = productElement.querySelector('[itemprop="name"]');
  const description = productElement.querySelector('[itemprop="description"]');
  const brand = productElement.querySelector('[itemprop="brand"] [itemprop="name"], [itemprop="brand"]');
  const image = productElement.querySelector('[itemprop="image"]');
  const price = productElement.querySelector('[itemprop="price"]');
  const material = productElement.querySelector('[itemprop="material"]');

  product.title = product.title || name?.textContent?.trim() || name?.content;
  product.description = product.description || description?.textContent?.trim() || description?.content;
  product.brand = product.brand || brand?.textContent?.trim() || brand?.content;
  product.image = product.image || image?.src || image?.content;
  product.price = product.price || price?.content || price?.textContent?.trim();
  product.material = product.material || material?.textContent?.trim() || material?.content;
}

// Extract from page content as fallback
function extractFromPage(product) {
  // Title from h1
  if (!product.title) {
    const h1 = document.querySelector('h1');
    if (h1) {
      product.title = h1.textContent.trim();
    }
  }

  // Try to find description from common selectors
  if (!product.description) {
    const descSelectors = [
      '[class*="product-description"]',
      '[class*="productDescription"]',
      '[id*="product-description"]',
      '[data-testid*="description"]',
      '.description',
      '#description'
    ];

    for (const selector of descSelectors) {
      const el = document.querySelector(selector);
      if (el) {
        product.description = el.textContent.trim().substring(0, 1000);
        break;
      }
    }
  }

  // Try to find main product image
  if (!product.image) {
    const imgSelectors = [
      '[class*="product-image"] img',
      '[class*="productImage"] img',
      '[data-testid*="product-image"] img',
      '.gallery img',
      '#product-image img',
      'main img[src*="product"]'
    ];

    for (const selector of imgSelectors) {
      const img = document.querySelector(selector);
      if (img?.src) {
        product.image = img.src;
        break;
      }
    }
  }

  // Try to find price
  if (!product.price) {
    const priceSelectors = [
      '[class*="price"]',
      '[data-testid*="price"]',
      '[itemprop="price"]'
    ];

    for (const selector of priceSelectors) {
      const el = document.querySelector(selector);
      if (el) {
        const text = el.textContent.trim();
        // Extract price-like pattern
        const priceMatch = text.match(/[\d,.]+/);
        if (priceMatch) {
          product.price = priceMatch[0];
          break;
        }
      }
    }
  }
}

// Helper to get image URL from various formats
function getImageUrl(image) {
  if (!image) return null;
  if (typeof image === 'string') return image;
  if (Array.isArray(image)) return image[0]?.url || image[0];
  return image.url || image.contentUrl || null;
}
