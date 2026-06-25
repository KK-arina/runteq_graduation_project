# lib/tasks/test_with_seed.rake
# db:test:prepare後にHabitTemplateが消える問題への対処。
# テスト実行後にseedsを再投入する専用タスク。
namespace :test do
  task with_seed: :environment do
    Rake::Task["db:environment:set"].invoke("RAILS_ENV=development")
    Rake::Task["db:test:prepare"].invoke
    Rake::Task["db:seed"].invoke
    Rake::Task["test"].invoke
  end
end
