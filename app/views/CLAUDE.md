# Views - AI Assistant Context

This document provides styling guidelines for all view templates in the Tariffik application.

## Brand Design Overview

Tariffik uses a retro/minimalist aesthetic with these core principles:
- **Borders over shadows** - Use `border border-gray-200` instead of `shadow-*`
- **Rounded corners** - `rounded-2xl` for cards, `rounded-xl` for inputs, `rounded-full` for buttons
- **High contrast** - Aubergine (`bg-brand-dark`) headers with white text for tables
- **Brand colors** - See main CLAUDE.md for full color palette

## Color Palette Quick Reference

| Color | Class | Use For |
|-------|-------|---------|
| Red | `bg-primary`, `text-primary`, `border-primary` | CTAs, active states, errors, links |
| Mint | `bg-brand-mint` | Success, complete, positive |
| Yellow | `bg-highlight` | Pending, warnings, info |
| Orange | `bg-brand-orange` | Secondary actions, accents |
| Aubergine | `bg-brand-dark` | Table headers, dark sections |

## Page Structure

### Standard Dashboard Page

```erb
<div class="max-w-6xl mx-auto">
  <%# Header with badge %>
  <div class="md:flex md:items-center md:justify-between mb-8">
    <div class="min-w-0 flex-1">
      <span class="inline-flex items-center rounded-full bg-brand-mint px-3 py-1 text-xs font-semibold text-brand-dark mb-2">PAGE TITLE</span>
      <h2 class="text-2xl font-bold leading-7 text-brand-dark sm:truncate sm:text-3xl sm:tracking-tight">
        Page Heading
      </h2>
      <p class="mt-1 text-sm text-gray-500">Optional description</p>
    </div>
    <div class="mt-4 flex md:ml-4 md:mt-0">
      <%# Action buttons here %>
    </div>
  </div>

  <%# Content %>
  <div class="bg-white rounded-2xl border border-gray-200 overflow-hidden">
    <%# Page content %>
  </div>
</div>
```

### Header Badge Colors by Section

| Section | Badge Color | Example |
|---------|-------------|---------|
| Dashboard/Home | `bg-brand-mint` | "YOUR ORDERS" |
| Product Lookups | `bg-brand-mint` | "PRODUCT LOOKUP" |
| Orders | `bg-brand-mint` | "ADD ORDER" |
| Developer/API | `bg-brand-dark text-white` | "API DASHBOARD" |
| Authentication | Varies by action | See Devise section |
| Settings | `bg-brand-dark text-white` | "SETTINGS" |

## Component Patterns

### Cards

```erb
<%# Outer card %>
<div class="bg-white rounded-2xl border border-gray-200 overflow-hidden">
  <%# Card content with padding %>
  <div class="p-6">
    Content here
  </div>
</div>

<%# Card with header and footer %>
<div class="bg-white rounded-2xl border border-gray-200 overflow-hidden">
  <div class="p-6">
    Content here
  </div>
  <div class="bg-gray-50 px-6 py-4 rounded-b-2xl">
    Footer content
  </div>
</div>
```

### Buttons

```erb
<%# Primary button (red) %>
<%= link_to "Action", path, class: "rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white hover:bg-primary-hover transition-colors" %>

<%# Secondary button (outline) %>
<%= link_to "Cancel", path, class: "rounded-full bg-white px-5 py-2.5 text-sm font-semibold text-brand-dark border border-gray-200 hover:bg-gray-50 transition-colors" %>

<%# Dark button (for light backgrounds) %>
<%= link_to "Action", path, class: "rounded-full bg-brand-dark px-5 py-2.5 text-sm font-semibold text-white hover:bg-dark-hover transition-colors" %>

<%# White button (for dark backgrounds) %>
<%= link_to "Action", path, class: "rounded-full bg-white px-6 py-3 text-sm font-semibold text-brand-dark hover:bg-gray-100 transition-colors" %>
```

### Form Inputs

```erb
<%# Text input %>
<%= f.text_field :name, class: "block w-full rounded-xl border border-gray-200 py-2.5 text-brand-dark placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-primary sm:text-sm px-4" %>

<%# Select dropdown %>
<%= f.select :status, options, {}, class: "block w-full rounded-xl border border-gray-200 py-2.5 text-brand-dark focus:ring-2 focus:ring-inset focus:ring-primary sm:text-sm px-4" %>

<%# Textarea %>
<%= f.text_area :description, rows: 4, class: "block w-full rounded-xl border border-gray-200 py-2.5 text-brand-dark placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-primary sm:text-sm px-4" %>

<%# Label %>
<%= f.label :name, class: "block text-sm font-medium leading-6 text-brand-dark" %>
```

### Tables

```erb
<div class="overflow-hidden rounded-2xl border border-gray-200">
  <table class="min-w-full">
    <thead class="bg-brand-dark">
      <tr>
        <th class="px-4 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">Column 1</th>
        <th class="px-4 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">Column 2</th>
        <th class="px-4 py-3 text-right text-xs font-medium text-white uppercase tracking-wider">Actions</th>
      </tr>
    </thead>
    <tbody class="bg-white divide-y divide-gray-200">
      <tr class="hover:bg-gray-50">
        <td class="px-4 py-4 text-sm text-gray-900">Content</td>
        <td class="px-4 py-4 text-sm text-gray-500">Content</td>
        <td class="px-4 py-4 text-sm text-right">
          <%= link_to "View", path, class: "text-primary hover:text-primary-hover font-medium" %>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

### Status Badges

```erb
<%# Success/Complete %>
<span class="inline-flex items-center rounded-full bg-brand-mint px-3 py-1 text-sm font-medium text-brand-dark">Complete</span>

<%# Pending/Processing %>
<span class="inline-flex items-center rounded-full bg-highlight px-3 py-1 text-sm font-medium text-brand-dark">Pending</span>

<%# Error/Failed %>
<span class="inline-flex items-center rounded-full bg-primary/10 px-3 py-1 text-sm font-medium text-primary">Failed</span>

<%# Info/Neutral %>
<span class="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700">Draft</span>
```

### Alert/Notice Messages

```erb
<%# Success alert %>
<div class="rounded-xl border border-brand-mint/30 bg-brand-mint/10 p-4">
  <div class="flex">
    <div class="shrink-0">
      <div class="inline-flex items-center justify-center rounded-lg bg-brand-mint size-8">
        <svg class="size-4 text-brand-dark" ...></svg>
      </div>
    </div>
    <div class="ml-3">
      <p class="text-sm text-brand-dark">Success message here</p>
    </div>
  </div>
</div>

<%# Error alert %>
<div class="rounded-xl border border-primary/30 bg-primary/5 p-4">
  <div class="flex">
    <div class="shrink-0">
      <div class="inline-flex items-center justify-center rounded-lg bg-primary size-8">
        <svg class="size-4 text-white" ...></svg>
      </div>
    </div>
    <div class="ml-3">
      <p class="text-sm text-brand-dark">Error message here</p>
    </div>
  </div>
</div>

<%# Warning/Info alert %>
<div class="rounded-xl border border-highlight bg-highlight/50 p-4">
  <div class="flex">
    <div class="shrink-0">
      <div class="inline-flex items-center justify-center rounded-lg bg-brand-orange size-8">
        <svg class="size-4 text-white" ...></svg>
      </div>
    </div>
    <div class="ml-3">
      <p class="text-sm text-brand-dark">Warning message here</p>
    </div>
  </div>
</div>
```

### Dark CTA Sections

```erb
<div class="bg-brand-dark rounded-2xl p-8 text-center">
  <h3 class="text-xl font-bold text-white mb-2">Upgrade Your Plan</h3>
  <p class="text-gray-300 mb-6">Get access to premium features</p>
  <%= link_to "Get Started", pricing_path, class: "inline-flex items-center rounded-full bg-white px-6 py-3 text-sm font-semibold text-brand-dark hover:bg-gray-100 transition-colors" %>
</div>
```

### Stats Cards

```erb
<div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
  <div class="bg-white rounded-2xl border border-gray-200 p-6">
    <dt class="text-sm font-medium text-gray-500">Total Orders</dt>
    <dd class="mt-1 text-3xl font-semibold text-brand-dark">42</dd>
  </div>
</div>
```

## Devise Authentication Views

All authentication pages follow this structure with colored header badges:

| Page | Badge Text | Badge Color |
|------|-----------|-------------|
| Sign In | WELCOME BACK | `bg-brand-mint` |
| Sign Up | GET STARTED | `bg-brand-mint` |
| Edit Profile | SETTINGS | `bg-brand-dark text-white` |
| Forgot Password | PASSWORD RESET | `bg-brand-orange` |
| Reset Password | NEW PASSWORD | `bg-brand-mint` |
| Resend Confirmation | CONFIRMATION | `bg-highlight` |
| Unlock Account | ACCOUNT LOCKED | `bg-brand-orange` |

### Devise Page Template

```erb
<div class="max-w-md mx-auto">
  <div class="text-center mb-8">
    <span class="inline-flex items-center rounded-full bg-brand-mint px-3 py-1 text-xs font-semibold text-brand-dark mb-2">BADGE TEXT</span>
    <h2 class="text-2xl font-bold text-brand-dark">Page Title</h2>
    <p class="mt-2 text-sm text-gray-500">Description text</p>
  </div>

  <div class="bg-white rounded-2xl border border-gray-200 overflow-hidden">
    <%= form_with ... class: "p-6 space-y-6" do |f| %>
      <%# Form fields %>

      <div class="bg-gray-50 -mx-6 -mb-6 px-6 py-4 rounded-b-2xl">
        <div class="flex items-center justify-between">
          <%= link_to "Back", path, class: "text-sm font-semibold text-brand-dark hover:text-brand-dark/70 transition-colors" %>
          <%= f.submit "Submit", class: "rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white hover:bg-primary-hover transition-colors cursor-pointer" %>
        </div>
      </div>
    <% end %>
  </div>

  <p class="mt-6 text-center text-sm text-gray-500">
    Helper text with <%= link_to "link", path, class: "font-semibold text-primary hover:text-primary-hover" %>
  </p>
</div>
```

## Tabs (Stimulus Controller)

Use the `tabs` Stimulus controller for tabbed interfaces:

```erb
<div data-controller="tabs">
  <div class="border-b border-gray-200 mb-6">
    <nav class="-mb-px flex space-x-8">
      <button type="button"
              data-tabs-target="tab"
              data-panel="url-panel"
              data-action="click->tabs#switch"
              class="border-b-2 border-primary text-primary py-4 px-1 text-sm font-medium">
        URL Lookup
      </button>
      <button type="button"
              data-tabs-target="tab"
              data-panel="photo-panel"
              data-action="click->tabs#switch"
              class="border-b-2 border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 py-4 px-1 text-sm font-medium">
        Photo Lookup
      </button>
    </nav>
  </div>

  <div id="url-panel" data-tabs-target="panel">
    <%# URL panel content %>
  </div>

  <div id="photo-panel" data-tabs-target="panel" class="hidden">
    <%# Photo panel content %>
  </div>
</div>
```

**Important:** Active tabs use `border-primary` and `text-primary`, not indigo colors.

## Empty States

```erb
<div class="text-center py-12">
  <svg class="mx-auto size-12 text-gray-400" ...></svg>
  <h3 class="mt-2 text-sm font-semibold text-brand-dark">No items</h3>
  <p class="mt-1 text-sm text-gray-500">Get started by creating a new item.</p>
  <div class="mt-6">
    <%= link_to "Create Item", new_item_path, class: "rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white hover:bg-primary-hover transition-colors" %>
  </div>
</div>
```

## Common Gotchas

1. **Never use inline JavaScript** - CSP blocks it. Use Stimulus controllers.
2. **Don't use shadow-* classes** - Use `border border-gray-200` instead.
3. **Active tab color** - Use `border-primary` and `text-primary`, not indigo.
4. **Password validation colors** - Use `text-brand-mint` for valid, `text-gray-400` for invalid.
5. **Form submit buttons need `cursor-pointer`** - Add it explicitly.
6. **Dark sections need light text** - `text-white` for headings, `text-gray-300` for body.

## File Organization

```
app/views/
├── layouts/
│   └── application.html.erb     # Base layout with navbar
├── shared/
│   ├── _navbar.html.erb         # Main navigation
│   └── _flash.html.erb          # Flash messages
├── devise/                      # Authentication views
│   ├── sessions/
│   ├── registrations/
│   ├── passwords/
│   ├── confirmations/
│   └── unlocks/
├── dashboard/
│   └── index.html.erb           # Main dashboard
├── orders/
│   ├── index.html.erb
│   ├── show.html.erb
│   └── new.html.erb
├── product_lookups/
│   ├── index.html.erb
│   ├── show.html.erb
│   ├── new.html.erb
│   ├── _product_lookup.html.erb
│   ├── _lookup_result.html.erb
│   ├── _status_badge.html.erb
│   └── _photo_form.html.erb
└── developer/
    ├── index.html.erb           # API dashboard
    └── upsell.html.erb          # Upgrade prompt
```
