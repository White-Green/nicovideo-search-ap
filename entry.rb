# frozen_string_literal: true

require "erb"
require "fileutils"
require "yaml"
require_relative "lib/input"
require_relative "lib/search"
require_relative "lib/user_yml"

user_html_erb = ERB.new(File.read(File.join(__dir__, "templates", "user.html.erb")))
video_html_erb = ERB.new(File.read(File.join(__dir__, "templates", "video.html.erb")))
video_md_erb = ERB.new(File.read(File.join(__dir__, "templates", "video.md.erb")))

user_html_erb.filename = "templates/user.html.erb"
video_html_erb.filename = "templates/video.html.erb"
video_md_erb.filename = "templates/video.md.erb"

OUTPUT_BASE = Pathname(__dir__).join("dist")
FileUtils.rm_rf(OUTPUT_BASE)
FileUtils.mkdir(OUTPUT_BASE)
FileUtils.cp_r(File.join(__dir__, "public"), OUTPUT_BASE.join("public"))

input = parse_input(YAML.load_file("./settings.yaml"))

FileUtils.mkdir_p(File.join(OUTPUT_BASE, "system", "users"))

input.each do |userid, setting|
    FileUtils.mkdir_p(File.join(OUTPUT_BASE, "system", "articles", userid))
    FileUtils.mkdir_p(File.join(OUTPUT_BASE, "public", "users", userid))

    search_result = search(
        query: setting.query,
        period_days: setting.period_days,
    )
    search_result.each do |video|
        FileUtils.mkdir_p(File.join(OUTPUT_BASE, "public", "articles", userid, video.id))

        video_md_path = File.join(OUTPUT_BASE, "system", "articles", userid, "#{video.id}.md")
        video_html_path = File.join(OUTPUT_BASE, "public", "articles", userid, video.id, "index.html")

        video_md = video_md_erb.result_with_hash(
            userid:,
            search_setting: setting,
            video:,
        )
        video_html = video_html_erb.result_with_hash(
            userid:,
            search_setting: setting,
            video:,
        )

        File.write(video_md_path, video_md)
        File.write(video_html_path, video_html)
    end

    user_yml_path = File.join(OUTPUT_BASE, "system", "users", "#{userid}.yml")
    user_html_path = File.join(OUTPUT_BASE, "public", "users", userid, "index.html")

    user_yml = make_user_yml(search_setting: setting, search_result:)
    user_html = user_html_erb.result_with_hash(
        search_setting: setting,
        search_result:,
    )

    File.write(user_yml_path, user_yml)
    File.write(user_html_path, user_html)
end
