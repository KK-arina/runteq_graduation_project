# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# 🆕 Stimulusコントローラーを明示的に登録
# pin_all_from が自動認識しない場合の手動登録
# "controllers/habit_checkbox_controller" → app/javascript/controllers/habit_checkbox_controller.js
pin "controllers/habit_checkbox_controller", to: "controllers/habit_checkbox_controller.js"
