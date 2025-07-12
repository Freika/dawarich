# Dawarich User Scenarios Documentation

## Overview
Dawarich is a self-hosted location history tracking application that allows users to import, visualize, and analyze their location data. This document describes all user scenarios for comprehensive test coverage.

## Application Context
- **Purpose**: Self-hosted alternative to Google Timeline/Location History
- **Tech Stack**: Rails 8, PostgreSQL, Hotwire (Turbo/Stimulus), Tailwind CSS with DaisyUI
- **Key Features**: Location tracking, data visualization, import/export, statistics, visits detection
- **Deployment**: Docker-based with self-hosted and cloud options

---

## 1. Authentication & User Management

### 1.1 User Registration (Non-Self-Hosted Mode)
**Scenario**: New user registration process
- **Entry Point**: Home page → Sign up link
- **Steps**:
  1. Navigate to registration form
  2. Fill in email, password, password confirmation
  3. Complete CAPTCHA (if enabled)
  4. Submit registration
  5. Receive confirmation (if email verification enabled)
- **Validation**: Email format, password strength, password confirmation match
- **Success**: User created, redirected to sign-in or dashboard

### 1.2 User Sign In/Out
**Scenario**: User authentication workflow
- **Entry Point**: Home page → Sign in link
- **Steps**:
  1. Navigate to sign-in form
  2. Enter email and password
  3. Optionally check "Remember me"
  4. Submit login
  5. Successful login redirects to map page
- **Demo Mode**: Special demo credentials (demo@dawarich.app / password)
- **Sign Out**: User can sign out from dropdown menu

### 1.3 Password Management
**Scenario**: Password reset and change functionality
- **Forgot Password**:
  1. Click "Forgot password" link
  2. Enter email address
  3. Receive reset email
  4. Follow reset link
  5. Set new password
- **Change Password** (when signed in):
  1. Navigate to account settings
  2. Provide current password
  3. Enter new password and confirmation
  4. Save changes

### 1.4 Account Settings
**Scenario**: User account management
- **Entry Point**: User dropdown → Account
- **Actions**:
  1. Update email address (requires current password)
  2. Change password
  3. View API key
  4. Generate new API key
  5. Theme selection (light/dark)
- **Self-Hosted**: Limited registration options

---

## 2. Map Functionality & Visualization

### 2.1 Main Map Interface
**Scenario**: Core location data visualization
- **Entry Point**: Primary navigation → Map
- **Features**:
  1. Interactive Leaflet map with multiple tile layers
  2. Time range selector (date/time inputs)
  3. Quick time range buttons (Today, Last 7 days, Last month)
  4. Navigation arrows for day-by-day browsing
  5. Real-time distance and points count display

### 2.2 Map Layers & Controls
**Scenario**: Map customization and layer management
- **Base Layers**:
  1. Switch between OpenStreetMap and OpenTopo
  2. Custom tile layer configuration
- **Overlay Layers**:
  1. Toggle points display
  2. Toggle route lines
  3. Toggle heatmap
  4. Toggle fog of war
  5. Toggle areas
  6. Toggle visits
- **Layer Control**: Expandable/collapsible layer panel

### 2.3 Map Data Display
**Scenario**: Location data visualization options
- **Points Rendering**:
  1. Raw mode (all points)
  2. Simplified mode (filtered by time/distance)
  3. Point clicking reveals details popup
  4. Battery level, altitude, velocity display
- **Routes**:
  1. Polyline connections between points
  2. Speed-colored routes option
  3. Configurable route opacity
  4. Route segment distance display

### 2.4 Map Settings & Configuration
**Scenario**: Map behavior customization
- **Settings Available**:
  1. Route opacity (0-100%)
  2. Meters between routes (distance threshold)
  3. Minutes between routes (time threshold)
  4. Fog of war radius
  5. Speed color scale customization
  6. Points rendering mode
- **Help Modals**: Contextual help for each setting

---

## 3. Location Data Import

### 3.1 Manual File Import
**Scenario**: Import location data from various sources
- **Entry Point**: Navigation → My data → Imports
- **Supported Sources**:
  1. Google Semantic History (JSON files)
  2. Google Records (Records.json)
  3. Google Phone Takeout (mobile device JSON)
  4. OwnTracks (.rec files)
  5. GeoJSON files
  6. GPX track files
- **Process**:
  1. Select source type
  2. Choose file(s) via file picker
  3. Upload and process (background job)
  4. Receive completion notification

### 3.2 Automatic File Watching
**Scenario**: Automatic import from watched directories
- **Setup**: Files placed in `/tmp/imports/watched/USER@EMAIL.TLD/`
- **Process**: System scans hourly for new files
- **Supported Formats**: GPX, JSON, REC files
- **Notification**: User receives import completion notifications

### 3.3 Photo Integration Import
**Scenario**: Import location data from photo EXIF data
- **Immich Integration**:
  1. Configure Immich URL and API key in settings
  2. Trigger import job
  3. System extracts GPS data from photos
  4. Creates location points from photo metadata
- **Photoprism Integration**:
  1. Configure Photoprism URL and API key
  2. Similar process to Immich
  3. Supports different date ranges

### 3.4 Import Management
**Scenario**: View and manage import history
- **Import List**: View all imports with status
- **Import Details**: Points count, processing status, errors
- **Import Actions**: View details, delete imports
- **Progress Tracking**: Real-time progress updates via WebSocket

---

## 4. Data Export

### 4.1 Export Creation
**Scenario**: Export location data in various formats
- **Entry Point**: Navigation → My data → Exports
- **Export Types**:
  1. GeoJSON format (default)
  2. GPX format
  3. Complete user data archive (ZIP)
- **Process**:
  1. Select export format
  2. Choose date range (optional)
  3. Submit export request
  4. Background processing
  5. Notification when complete

### 4.2 Export Management
**Scenario**: Manage created exports
- **Export List**: View all exports with details
- **Export Actions**:
  1. Download completed exports
  2. Delete old exports
  3. View export status
- **File Information**: Size, creation date, download links

### 4.3 Complete Data Export
**Scenario**: Export all user data for backup/migration
- **Trigger**: Settings → Users → Export data
- **Content**: All user data, settings, files in ZIP format
- **Use Case**: Account migration, data backup
- **Process**: Background job, notification on completion

---

## 5. Statistics & Analytics

### 5.1 Statistics Dashboard
**Scenario**: View travel statistics and analytics
- **Entry Point**: Navigation → Stats
- **Key Metrics**:
  1. Total distance traveled
  2. Total tracked points
  3. Countries visited
  4. Cities visited
  5. Reverse geocoding statistics
- **Display**: Cards with highlighted numbers and units

### 5.2 Yearly/Monthly Breakdown
**Scenario**: Detailed statistics by time period
- **View Options**:
  1. Statistics by year
  2. Monthly breakdown within years
  3. Distance traveled per period
  4. Points tracked per period
- **Actions**: Update statistics (background job)

### 5.3 Statistics Management
**Scenario**: Update and manage statistics
- **Manual Updates**:
  1. Update all statistics
  2. Update specific year/month
  3. Background job processing
- **Automatic Updates**: Triggered by data imports

---

## 6. Trips Management

### 6.1 Trip Creation
**Scenario**: Create and manage travel trips
- **Entry Point**: Navigation → Trips → New trip
- **Trip Properties**:
  1. Trip name
  2. Start date/time
  3. End date/time
  4. Notes (rich text)
- **Validation**: Date ranges, required fields

### 6.2 Trip Visualization
**Scenario**: View trip details and route
- **Trip View**:
  1. Interactive map with trip route
  2. Trip statistics (distance, duration)
  3. Countries visited during trip
  4. Photo integration (if configured)
- **Photo Display**: Grid layout with links to photo sources

### 6.3 Trip Management
**Scenario**: Edit and manage existing trips
- **Trip List**: Paginated view of all trips
- **Trip Actions**:
  1. Edit trip details
  2. Delete trips
  3. View trip details
- **Background Processing**: Distance and route calculations

---

## 7. Visits & Places (Beta Feature)

### 7.1 Visit Suggestions
**Scenario**: Automatic visit detection and suggestions
- **Process**: Background job analyzes location data
- **Detection**: Identifies places where user spent time
- **Suggestions**: Creates suggested visits for review
- **Notifications**: User receives visit suggestion notifications

### 7.2 Visit Management
**Scenario**: Review and manage visit suggestions
- **Entry Point**: Navigation → My data → Visits & Places
- **Visit States**:
  1. Suggested (pending review)
  2. Confirmed (accepted)
  3. Declined (rejected)
- **Actions**: Confirm, decline, or edit visits
- **Filtering**: View by status, order by date

### 7.3 Places Management
**Scenario**: Manage detected places
- **Place List**: All places created by visit suggestions
- **Place Details**: Name, coordinates, creation date
- **Actions**: Delete places (deletes associated visits)
- **Integration**: Places linked to visits

### 7.4 Areas Creation
**Scenario**: Create custom areas for visit detection
- **Map Interface**: Draw areas on map
- **Area Properties**:
  1. Name
  2. Radius
  3. Coordinates (center point)
- **Purpose**: Improve visit detection accuracy

---

## 8. Points Management

### 8.1 Points List
**Scenario**: View and manage individual location points
- **Entry Point**: Navigation → My data → Points
- **Display**: Paginated table with point details
- **Point Information**:
  1. Timestamp
  2. Coordinates
  3. Accuracy
  4. Source import
- **Filtering**: Date range, import source

### 8.2 Point Actions
**Scenario**: Individual point management
- **Point Details**: Click point for popup with full details
- **Actions**:
  1. Delete individual points
  2. Bulk delete points
  3. View point source
- **Map Integration**: Points clickable on map

---

## 9. Notifications System

### 9.1 Notification Types
**Scenario**: System notifications for various events
- **Import Notifications**:
  1. Import completed
  2. Import failed
  3. Import progress updates
- **Export Notifications**:
  1. Export completed
  2. Export failed
- **System Notifications**:
  1. Visit suggestions available
  2. Statistics updates completed
  3. Background job failures

### 9.2 Notification Management
**Scenario**: View and manage notifications
- **Entry Point**: Bell icon in navigation
- **Notification List**: All notifications with timestamps
- **Actions**:
  1. Mark as read
  2. Mark all as read
  3. Delete notifications
  4. Delete all notifications
- **Display**: Badges for unread count

---

## 10. Settings & Configuration

### 10.1 Integration Settings
**Scenario**: Configure external service integrations
- **Entry Point**: Navigation → Settings → Integrations
- **Immich Integration**:
  1. Configure Immich URL
  2. Set API key
  3. Test connection
- **Photoprism Integration**:
  1. Configure Photoprism URL
  2. Set API key
  3. Test connection

### 10.2 Map Settings
**Scenario**: Configure map appearance and behavior
- **Entry Point**: Settings → Map
- **Options**:
  1. Custom tile layer URL
  2. Map layer name
  3. Distance unit (km/miles)
  4. Tile usage statistics
- **Preview**: Real-time map preview

### 10.3 User Settings
**Scenario**: Personal preferences and account settings
- **Theme**: Light/dark mode toggle
- **API Key**: View and regenerate API key
- **Visits Settings**: Enable/disable visit suggestions
- **Route Settings**: Default route appearance

---

## 11. Admin Features (Self-Hosted Only)

### 11.1 User Management
**Scenario**: Admin user management in self-hosted mode
- **Entry Point**: Settings → Users (admin only)
- **User Actions**:
  1. Create new users
  2. Edit user details
  3. Delete users
  4. View user statistics
- **User Creation**: Email and password setup

### 11.2 Background Jobs Management
**Scenario**: Admin control over background processing
- **Entry Point**: Settings → Background Jobs
- **Job Types**:
  1. Reverse geocoding jobs
  2. Statistics calculation
  3. Visit suggestion jobs
- **Actions**: Start/stop background jobs, view job status

### 11.3 System Administration
**Scenario**: System-level administration
- **Sidekiq Dashboard**: Background job monitoring
- **System Settings**: Global configuration options
- **User Data Management**: Export/import user data

---

## 12. API Functionality

### 12.1 Location Data API
**Scenario**: Programmatic location data submission
- **Endpoints**: RESTful API for location data
- **Authentication**: API key based
- **Supported Apps**:
  1. Dawarich iOS app
  2. Overland
  3. OwnTracks
  4. GPSLogger
  5. Custom applications

### 12.2 Data Retrieval API
**Scenario**: Retrieve location data via API
- **Use Cases**: Third-party integrations, mobile apps
- **Data Formats**: JSON, GeoJSON
- **Authentication**: API key required

---

## 13. Error Handling & Edge Cases

### 13.1 Import Errors
**Scenario**: Handle various import failure scenarios
- **File Format Errors**: Unsupported or corrupted files
- **Processing Errors**: Background job failures
- **Network Errors**: Failed downloads or API calls
- **User Feedback**: Error notifications with details

### 13.2 System Errors
**Scenario**: Handle system-level errors
- **Database Errors**: Connection issues, constraints
- **Storage Errors**: File system issues
- **Memory Errors**: Large data processing
- **User Experience**: Graceful error messages

### 13.3 Data Validation
**Scenario**: Validate user input and data integrity
- **Coordinate Validation**: Valid latitude/longitude
- **Time Validation**: Logical timestamp values
- **File Validation**: Supported formats and sizes
- **User Input**: Form validation and sanitization

---

## 14. Performance & Scalability

### 14.1 Large Dataset Handling
**Scenario**: Handle users with large amounts of location data
- **Map Performance**: Efficient rendering of many points
- **Data Processing**: Batch processing for imports
- **Memory Management**: Streaming for large files
- **User Experience**: Progress indicators, pagination

### 14.2 Background Processing
**Scenario**: Asynchronous task handling
- **Job Queues**: Sidekiq for background jobs
- **Progress Tracking**: Real-time job status
- **Error Recovery**: Retry mechanisms
- **User Feedback**: Job completion notifications

---

## 15. Mobile & Responsive Design

### 15.1 Mobile Interface
**Scenario**: Mobile-optimized user experience
- **Responsive Design**: Mobile-first approach
- **Touch Interactions**: Map gestures, mobile-friendly controls
- **Mobile Navigation**: Collapsible menus
- **Performance**: Optimized for mobile devices

### 15.2 Cross-Platform Compatibility
**Scenario**: Consistent experience across devices
- **Browser Support**: Modern browser compatibility
- **Device Support**: Desktop, tablet, mobile
- **Feature Parity**: Full functionality across platforms

---

## Test Scenarios Priority

### High Priority (Core Functionality)
1. User authentication (sign in/out)
2. Map visualization with basic controls
3. Data import (at least one source type)
4. Basic settings configuration
5. Point display and interaction

### Medium Priority (Extended Features)
1. Trip management
2. Visit suggestions and management
3. Data export
4. Statistics viewing
5. Notification system

### Low Priority (Advanced Features)
1. Admin functions
2. API functionality
3. Complex map settings
4. Background job management
5. Error handling edge cases

---

## Notes for Test Implementation

1. **Test Data**: Use factory-generated test data for consistency
2. **API Testing**: Include both UI and API endpoint testing
3. **Background Jobs**: Test asynchronous processing
4. **File Handling**: Test various file formats and sizes
5. **Responsive Testing**: Include mobile viewport testing
6. **Performance Testing**: Test with large datasets
7. **Error Scenarios**: Include negative test cases
8. **Browser Compatibility**: Test across different browsers
