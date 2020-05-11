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
#  'https://hooks.zapier.com/hooks/catch/6688770/o55rf2n/'
]

COHORT_JOB_TAG = 'EF Cohort'

LEVER_BOT_USER = 'e6414a92-e785-46eb-ad30-181c18db19b5'

CSV_EXPORT_HEADERS = %w[
  contact name application__name application__createdAt__datetime __empty__ application__type application__posting id stageChanges stage__text stage__id origin sources tags links archived__archivedAt__datetime archived__reason  owner__name  application__createdAt__datetime
  feedback_summary__ability_completed_at__datetime
  feedback_summary__ability_completed_by
  feedback_summary__ability_rating
  feedback_summary__app_review_ceo_cto
  feedback_summary__app_review_completed_at__datetime
  feedback_summary__app_review_completed_by
  feedback_summary__app_review_edge
  feedback_summary__app_review_industry
  feedback_summary__app_review_rating
  feedback_summary__app_review_software_hardware
  feedback_summary__app_review_talker_doer
  feedback_summary__app_review_technology
  feedback_summary__behaviour_completed_at__datetime
  feedback_summary__behaviour_completed_by
  feedback_summary__behaviour_rating
  feedback_summary__coffee_completed_at__datetime
  feedback_summary__coffee_completed_by
  feedback_summary__coffee_edge
  feedback_summary__coffee_eligible
  feedback_summary__coffee_gender
  feedback_summary__coffee_rating
  feedback_summary__coffee_software_hardware
  feedback_summary__debrief_completed_at__datetime
  feedback_summary__debrief_edge
  feedback_summary__debrief_healthcare
  feedback_summary__debrief_industry
  feedback_summary__debrief_rating
  feedback_summary__debrief_software_hardware
  feedback_summary__debrief_talker_doer
  feedback_summary__debrief_technology
  feedback_summary__debrief_visa_exposure
  feedback_summary__f2f_ceo_cto
  feedback_summary__has_ability
  feedback_summary__has_app_review
  feedback_summary__has_behaviour
  feedback_summary__has_coffee
  feedback_summary__has_debrief
  feedback_summary__has_phone_screen
  feedback_summary__phone_screen_completed_at__datetime
  feedback_summary__phone_screen_completed_by
  feedback_summary__phone_screen_rating
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
