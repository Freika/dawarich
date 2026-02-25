/**
 * Constants for e2e tests
 * These API keys match those set in lib/tasks/demo.rake
 */

export const API_KEYS = {
  DEMO_USER: "demo_api_key_001",
  FAMILY_MEMBER_1: "family_member_1_api_key",
  FAMILY_MEMBER_2: "family_member_2_api_key",
  FAMILY_MEMBER_3: "family_member_3_api_key",
}

export const TEST_USERS = {
  DEMO: {
    email: "demo@dawarich.app",
    password: "password",
    apiKey: API_KEYS.DEMO_USER,
  },
  FAMILY_1: {
    email: "family.member1@dawarich.app",
    password: "password",
    apiKey: API_KEYS.FAMILY_MEMBER_1,
  },
  FAMILY_2: {
    email: "family.member2@dawarich.app",
    password: "password",
    apiKey: API_KEYS.FAMILY_MEMBER_2,
  },
  FAMILY_3: {
    email: "family.member3@dawarich.app",
    password: "password",
    apiKey: API_KEYS.FAMILY_MEMBER_3,
  },
}

// Test location coordinates (Berlin, Germany area)
export const TEST_LOCATIONS = {
  BERLIN_CENTER: { lat: 52.52, lon: 13.405 },
  BERLIN_NORTH: { lat: 52.54, lon: 13.405 },
  BERLIN_SOUTH: { lat: 52.5, lon: 13.405 },
}
