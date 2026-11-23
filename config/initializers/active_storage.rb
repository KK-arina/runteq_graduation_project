# config/initializers/active_storage.rb
#
# ==============================================================================
# Active Storage の画像変換（variant）を無効にする
# ==============================================================================
#
# 【なぜ無効にするのか】
#   Rails は起動時に、画像変換用の image_processing gem が無いと
#   「Generating image variants require the image_processing gem」という警告を出す。
#   HabitFlow は画像のリサイズ・変換（.variant）を使っていないため、
#   使わない gem を追加するのではなく、画像変換の機能そのものを無効にする。
#
# 【将来、画像変換が必要になったら】
#   Gemfile の image_processing のコメントを外して bundle install し、
#   この設定を削除する。無効のまま .variant を呼ぶとエラーになるので気づける。
Rails.application.config.active_storage.variant_processor = :disabled
