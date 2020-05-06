# frozen_string_literal: true

COHORT_JOBS = [
  {name: 'bangalore', posting_id: '23bf8c07-b32e-483f-9007-1b9c2a004eb6'},
  {name: 'london', posting_id: 'c404cfc6-0621-4fce-9e76-5d908e36fd9c'},
  {name: 'singapore', posting_id: '3b2c714a-edee-4fd0-974d-413bae32c818'},
  {name: 'paris', posting_id: 'e23deb1a-c0ab-43b8-9a3a-e47e3cca0970'},
  {name: 'berlin', posting_id: 'b9c2b6b8-3d82-4c45-9b06-b549d223b017'},
  {name: 'toronto', posting_id: '0b785d4c-3a6e-4597-829e-fcafb06cae2b'}
]

OPPORTUNITY_CHANGED_WEBHOOK_URLS = [
  # Zap: New app + debrief info - https://zapier.com/app/history?root_id=80954860
  'https://hooks.zapier.com/hooks/catch/3678640/o1tu42p/'
]

FULL_WEBHOOK_URLS = [
  'https://hooks.zapier.com/hooks/catch/6688770/o55rf2n/'
]

COHORT_JOB_TAG = 'EF Cohort'

LEVER_BOT_USER = 'e6414a92-e785-46eb-ad30-181c18db19b5'

CSV_EXPORT_HEADERS = %w[
  id 
]

# AUTO_.. prefixes are used for auto-added attributes relating to the candidate data 
# BOT_.. prefixes are used for auto-added attributed used by our bot
#        - ignored for the purpose of detecting data changes
AUTO_TAG_PREFIX = '🤖 '
AUTO_LINK_PREFIX = 'http://🤖/'
BOT_LINK_PREFIX = AUTO_LINK_PREFIX + 'bot/'
BOT_METADATA_PREFIX = BOT_LINK_PREFIX + 'data/'

TAG_ASSIGN_TO_LOCATION_NONE_FOUND = AUTO_TAG_PREFIX + 'No location tag'
TAG_ASSIGN_TO_LOCATION_PREFIX = AUTO_TAG_PREFIX + 'Auto-assigned to cohort: '
TAG_ASSIGNED_TO_LOCATION = AUTO_TAG_PREFIX + 'Auto-assigned to cohort'

TAG_DUPLICATE_OPPS_PREFIX = AUTO_TAG_PREFIX + "Duplicate: "

TAG_LINKEDIN_OPTOUT = AUTO_TAG_PREFIX + 'LinkedIn InMail likely decline'
TAG_LINKEDIN_OPTIN_LIKELY = AUTO_TAG_PREFIX + 'LinkedIn InMail potential accept'
TAG_LINKEDIN_OPTIN = AUTO_TAG_PREFIX + 'LinkedIn InMail accept awaiting followup'

LINK_ALL_FEEDBACK_SUMMARY_PREFIX = AUTO_LINK_PREFIX + 'feedback/all/'

# deprecated: now storing under BOT_METADATA
BOT_TAG_PREFIX = '🤖 [bot] '
LAST_CHANGE_TAG_PREFIX = BOT_TAG_PREFIX + "last change detected: "
TAG_CHECKSUM_PREFIX = BOT_TAG_PREFIX + "tag checksum: "
LINK_CHECKSUM_PREFIX = BOT_LINK_PREFIX + "checksum/"
TAG_LINKEDIN_OPTOUT_OLD = AUTO_TAG_PREFIX + 'LinkedIn InMail decline (suspected)'
