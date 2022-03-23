defmodule Lightning.AdaptorRegistryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Lightning.AdaptorRegistry

  describe "start_link/1" do
    # AdaptorRegistry is a GenServer, and so stubbed (external) functions must 
    # be mocked globally. See: https://github.com/edgurgel/mimic#private-and-global-mode
    setup :set_mimic_from_context

    setup do
      stub(:hackney)

      :ok
    end

    test "uses cache from a specific location" do
      {:ok, fd, file_path} = Temp.open("cache.json")

      IO.write(fd, ~S"""
        [{
          "latest": "3.0.5",
          "name": "@openfn/language-dhis2",
          "repo": "git+https://github.com/openfn/language-dhis2.git",
          "versions": []
        }]
      """)

      File.close(fd)
      start_supervised!({AdaptorRegistry, [name: :test_adaptor_registry, use_cache: file_path]})

      results = AdaptorRegistry.all(:test_adaptor_registry)
      assert length(results) == 1

      File.rm(file_path)
    end

    test "retrieves a list of adaptors when caching is disabled" do
      # :hackney.request(request.method, request.url, request.headers, request.body, hn_options)
      expect(:hackney, :request, fn
        :get, "https://registry.npmjs.org/-/user/openfn/package", [], "", [pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, File.read!("test/fixtures/openfn-packages-npm.json")}
      end)

      expected_adaptors = [
        "@openfn/language-asana",
        "@openfn/language-common",
        "@openfn/language-commcare",
        "@openfn/language-dhis2",
        "@openfn/language-http",
        "@openfn/language-salesforce"
      ]

      stub(:hackney, :body, fn :adaptor, _timeout ->
        {:ok, File.read!("test/fixtures/language-common-npm.json")}
      end)

      stub(:hackney, :request, fn
        :get, "https://registry.npmjs.org/" <> adaptor, [], "", [pool: :default] ->
          assert adaptor in expected_adaptors
          {:ok, 200, "headers", :adaptor}
      end)

      start_supervised!({AdaptorRegistry, [name: :test_adaptor_registry, use_cache: false]})

      results = AdaptorRegistry.all(:test_adaptor_registry)

      assert length(results) == 6

      versions = [
        %{version: "1.1.0"},
        %{version: "1.1.1"},
        %{version: "1.2.0"},
        %{version: "1.2.1"},
        %{version: "1.2.2"},
        %{version: "1.2.4"},
        %{version: "1.2.5"},
        %{version: "1.2.6"},
        %{version: "1.2.7"},
        %{version: "1.2.8"},
        %{version: "1.4.0"},
        %{version: "1.4.1"},
        %{version: "1.4.2"},
        %{version: "1.5.0"},
        %{version: "1.6.0"},
        %{version: "1.6.1"},
        %{version: "1.6.2"}
      ]

      assert %{
               name: "@openfn/language-common",
               repo: "git+https://github.com/OpenFn/language-common.git",
               latest: "1.6.2",
               versions: versions
             } in results

      assert AdaptorRegistry.versions_for(:test_adaptor_registry, "@openfn/language-common") ==
               versions

      assert AdaptorRegistry.versions_for(:test_adaptor_registry, "@openfn/language-foobar") ==
               nil
    end
  end
end
