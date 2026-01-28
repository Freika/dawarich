# frozen_string_literal: true

# Configuration for the Supporter Verification Service
# This service is used to verify if a user is a supporter via Patreon, GitHub Sponsors, or Ko-fi
#
# Environment variables:
#   SUPPORTER_VERIFICATION_URL - The URL of the verification service API
#                                 (default: https://verify.dawarich.app/api/v1/verify)
#
# The verification service stores hashed emails only (SHA256) and returns
# supporter status without exposing actual email addresses.

SUPPORTER_VERIFICATION_URL = ENV.fetch('SUPPORTER_VERIFICATION_URL', 'https://verify.dawarich.app/api/v1/verify')
