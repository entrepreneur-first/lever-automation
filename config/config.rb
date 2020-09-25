# frozen_string_literal: true

COHORT_JOBS = [
  # next cohort postings
  # .. include tag: <location> to auto-assign based on tags
  {posting_id: 'b65f18c3-27f3-4812-92af-b0f66a5694b8', cohort: 'BA5',  tag: 'bangalore'},
  {posting_id: '9d662b61-de96-40c0-bb81-89d3f84ef1b2', cohort: 'LD16', tag: 'london'},
  {posting_id: 'fc7a7137-4433-4522-9c51-61bc8fde864f', cohort: 'SG9',  tag: 'singapore'},
  {posting_id: '6fe2ce13-2296-4acd-8b1e-2e5b4a14c58c', cohort: 'PA6',  tag: 'paris'},
  {posting_id: '394f29ca-7054-4e57-bc64-54886ce98eb2', cohort: 'BE7',  tag: 'berlin'},
  {posting_id: '4a924c27-5737-48fe-8d45-48a1163745c0', cohort: 'TO2',  tag: 'toronto'},

  # previous cohort postings
  {posting_id: 'd924991a-614a-4cde-ab4e-600a5fce2af4', cohort: 'BA4'}, # Bangalore Pool
  {posting_id: '23bf8c07-b32e-483f-9007-1b9c2a004eb6', cohort: 'BA4'},
  {posting_id: '46ac9eaf-31d1-4b41-8b2b-1d43014aacc0', cohort: 'BE5'},
  {posting_id: 'b9c2b6b8-3d82-4c45-9b06-b549d223b017', cohort: 'BE6'},
  {posting_id: 'ee0ed9ee-7148-4967-a402-e6962e4c6bc1', cohort: 'BE5'}, # Berlin Pool
  {posting_id: 'b88a4eba-bbb4-492e-a77a-f36c1328d9dd', cohort: 'LD14'},
  {posting_id: 'c404cfc6-0621-4fce-9e76-5d908e36fd9c', cohort: 'LD15'},
  {posting_id: 'ad446668-5642-4b1f-b027-7798a7472db7', cohort: 'LD14'}, # London Pool
  {posting_id: 'c88fa46b-b06c-47e3-81d6-4e63078fd509', cohort: 'PA4'},
  {posting_id: 'e57c60e3-f129-4088-9c7f-1e9ea270fbf6', cohort: 'PA4'}, # Paris Pool
  {posting_id: 'f7a6dd4e-9f3a-4633-b676-15abe9165025', cohort: 'SG8'}, # Singapore Pool
  {posting_id: '3b2c714a-edee-4fd0-974d-413bae32c818', cohort: 'SG8'},
  {posting_id: 'df1e30e5-c08d-47bd-bd43-8f3eaf96163e', cohort: 'TO1'}, # Toronto Pool
  {posting_id: 'e23deb1a-c0ab-43b8-9a3a-e47e3cca0970', cohort: 'PA5'},
  {posting_id: 'faeae4e5-6529-4f95-b705-3f9974bb682c', cohort: 'PA7'},
  {posting_id: '3eaed985-8d2e-4a88-b6bb-a1295cb57373', cohort: 'PA8'}, 
  {posting_id: '210435bd-7ff7-4ced-a3e8-dbeed1c19f08', cohort: 'PA9'},
  {posting_id: '0b785d4c-3a6e-4597-829e-fcafb06cae2b', cohort: 'TO1'},


]

COHORT_JOB_TAG = 'EF Cohort'

TEST_JOB = '51e8be45-30e9-4465-97c0-64cd2a9963db'
TEST_OPPORTUNITY_EMAIL = 'test@example.com'

LEVER_BOT_USER = 'e6414a92-e785-46eb-ad30-181c18db19b5'

COFFEE_FEEDBACK_FORM = '14598edb-390d-41e7-999c-fd56c3c4fe65'

OFFER_STAGES = ["offer", "b2422e70-d9d5-4c49-ade5-c007bc094265"]
OFFER_ACCEPTED_STAGES = ["87f72880-e6b5-455e-9c8f-acee90bb9c92"]

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

TAG_LINKEDIN_OPTOUT = AUTO_TAG_PREFIX + 'LinkedIn InMail likely decline'
TAG_LINKEDIN_OPTIN_LIKELY = AUTO_TAG_PREFIX + 'LinkedIn InMail potential accept'
TAG_LINKEDIN_OPTIN = AUTO_TAG_PREFIX + 'LinkedIn InMail accept awaiting followup'

LINK_ALL_FEEDBACK_SUMMARY_PREFIX = AUTO_LINK_PREFIX + 'feedback/all/'

TAG_DUPLICATE_ARCHIVED = AUTO_TAG_PREFIX + 'Archived duplicate'
TAG_DUPLICATE_PREFIX = AUTO_TAG_PREFIX + "Duplicate: "
TAG_ORIGINAL_PREFIX = AUTO_TAG_PREFIX + '[Original] '
TAG_HISTORIC_PREFIX = AUTO_TAG_PREFIX + '[Historic] '

# ~6 months
ORIGINAL_TIMEOUT = 15552000000

# deprecated: now storing under BOT_METADATA
BOT_TAG_PREFIX = '🤖 [bot] '
LAST_CHANGE_TAG_PREFIX = BOT_TAG_PREFIX + "last change detected: "
TAG_CHECKSUM_PREFIX = BOT_TAG_PREFIX + "tag checksum: "
LINK_CHECKSUM_PREFIX = BOT_LINK_PREFIX + "checksum/"
TAG_LINKEDIN_OPTOUT_OLD = AUTO_TAG_PREFIX + 'LinkedIn InMail decline (suspected)'

# deprecated: webhooks
OPPORTUNITY_CHANGED_WEBHOOK_URLS = [
  ## Zap: New app + debrief info - https://zapier.com/app/history?root_id=80954860
  #'https://hooks.zapier.com/hooks/catch/3678640/o1tu42p/'
]

FULL_WEBHOOK_URLS = [
#  'https://hooks.zapier.com/hooks/catch/6688770/o55rf2n/'
]

# deprecated: CSV export
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
