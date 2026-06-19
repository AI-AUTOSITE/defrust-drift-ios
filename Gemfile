source "https://rubygems.org"

# Pinned to 2.235.0: fastlane 2.236.x has a regression where upload_to_testflight
# fails on Xcode 26 with "The file couldn't be opened because it isn't in the
# correct format. (259)" (fastlane issue #30065).
gem "fastlane", "2.235.0"

# fastlane 2.235.0 needs multi_json at runtime but doesn't declare it as a direct
# dependency (fixed in 2.236.0, which we can't use). Add it explicitly.
gem "multi_json"
