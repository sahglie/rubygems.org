require 'test_helper'

class HostessTest < ActiveSupport::TestCase
  def app
    Hostess.new
  end

  def touch(path, local = true)
    Hostess.local = local
    if local
      path = Gemcutter.server_path(path)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
    else
      net_resp = FakeWeb::Responder.new(:get, "/", {}, 1).response
      s3_resp = AWS::S3::S3Object::Response.new(net_resp)
      stub(VaultObject).value(path, anything) { s3_resp }
    end
  end

  setup do
    Hostess.local = false
  end

  %w[/prerelease_specs.4.8.gz
     /latest_specs.4.8.gz
     /specs.4.8.gz
     /Marshal.4.8.Z
     /latest_specs.4.8
     /prerelease_specs.4.8
     /specs.4.8
     /Marshal.4.8
     /quick/Marshal.4.8/test-0.0.0.gemspec.rz
     /quick/index
     /quick/index.rz
     /quick/latest_index
     /quick/latest_index.rz
     /quick/rubygems-update-1.3.5.gemspec.rz
     /yaml
     /yaml.Z
     /yaml.z
  ].each do |index|
    should "serve up #{index} locally" do
      touch index, true
      get index
      assert_equal 200, last_response.status
    end

    should "serve up #{index} remotely" do
      touch index, false
      get index
      assert_equal 302, last_response.status
    end
  end

  context "with gem" do
    setup do
      @download_count = Download.count
      @file = "/gems/test-0.0.0.gem"
      @rubygem = Factory(:rubygem, :name => "test")
      @version = Factory(:version, :rubygem => @rubygem, :number => "0.0.0")
    end

    should "increase download count" do
      get @file

      assert_equal @download_count + 1, Download.count
      assert_equal 1, @rubygem.reload.downloads
      assert_equal 1, @version.reload.downloads_count
    end

    should "redirect to s3 for a gem within a day old" do
      get @file

      assert_equal "http://test.s3.rubygems.org#{@file}", last_response.headers["Location"]
      assert_equal 302, last_response.status
    end

    should "redirect to cf for a gem within a day old" do
      @version.update_attribute(:updated_at, 1.day.ago)
      get @file

      assert_equal "http://test.s3.rubygems.org#{@file}", last_response.headers["Location"]
      assert_equal 302, last_response.status
    end
  end

  should "not be able to find bad gem" do
    get "/gems/rails-3.0.0.gem"
    assert_equal 404, last_response.status
  end

  should "serve up gem locally" do
    Hostess.local = true
    download_count = Download.count
    file = "/gems/test-0.0.0.gem"
    FileUtils.cp gem_file.path, Gemcutter.server_path("gems")

    rubygem = Factory(:rubygem, :name => "test")
    version = Factory(:version, :rubygem => rubygem, :number => "0.0.0")

    get file
    assert_equal 200, last_response.status
    assert_equal download_count + 1, Download.count
    assert_equal 1, rubygem.reload.downloads
    assert_equal 1, version.reload.downloads_count
  end
end
