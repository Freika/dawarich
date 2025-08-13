# Trials Feature Checklist

## ✅ Already Implemented

- [x] **7-day trial activation** - `set_trial` method sets `status: :trial` and `active_until: 7.days.from_now`
- [x] **Welcome email** - Sent immediately after registration
- [x] **Scheduled emails** - Feature exploration (day 2), trial expires soon (day 5), trial expired (day 7)
- [x] **Trial status enum** - `{ inactive: 0, active: 1, trial: 3 }`
- [x] **Navbar Trial Display** - Show number of days left in trial at subscribe button
- [x] **Account Deletion Cleanup** - User deletes account during trial, cleanup scheduled emails
  - [x] Worker to not send emails if user is deleted

## ❌ Missing/TODO Items

### Core Requirements
- [x] **Specs** - Add specs for all implemented features
  - [x] User model trial callbacks and methods
  - [x] Trial webhook job with JWT encoding
  - [x] Mailer sending job for all email types
  - [x] JWT encoding service


## Manager (separate application)
- [ ] **Manager Webhook** - Create user in Manager service after registration
- [ ] **Manager callback** - Manager should daily check user statuses and once trial is expired, update user status to inactive in Dawarich
- [ ] **Trial Credit** - Should trial time be credited to first paid month?
  - [ ] Yes, Manager after payment adds subscription duration to user's active_until
- [ ] **User Reactivation** - Handle user returning after trial expired
