defmodule BuildCalculator.Wiki.TemplateTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.Template

  describe "find_one/2" do
    test "reads named parameters" do
      wikitext = """
      {{feat
      |type=general
      |prereq=[[strength]] 13+
      |use=combat mode
      }}
      """

      assert {:ok, template} = Template.find_one(wikitext, "feat")

      assert template.params == %{
               "type" => "general",
               "prereq" => "[[strength]] 13+",
               "use" => "combat mode"
             }
    end

    test "keeps pipes that belong to a wiki link inside the value" do
      wikitext = "{{spell|school=[[evocation|Evocation school]]|range=l}}"

      assert {:ok, template} = Template.find_one(wikitext, "spell")
      assert template.params["school"] == "[[evocation|Evocation school]]"
      assert template.params["range"] == "l"
    end

    test "keeps nested templates and tables inside the value" do
      wikitext = """
      {{spell|desc=Deals {{tl|1d6|per level}} damage.
      {| class="wikitable"
      ! level !! missiles
      |-
      | 1 || 1
      |}
      |range=l}}
      """

      assert {:ok, template} = Template.find_one(wikitext, "spell")
      assert template.params["range"] == "l"
      assert template.params["desc"] =~ "{{tl|1d6|per level}}"
      assert template.params["desc"] =~ "| 1 || 1"
    end

    test "splits on the first top-level equals sign only" do
      wikitext = "{{feat|desc=a == b, and c = d}}"

      assert {:ok, template} = Template.find_one(wikitext, "feat")
      assert template.params["desc"] == "a == b, and c = d"
    end

    test "matches the template name case-insensitively but not as a prefix" do
      assert {:ok, _template} = Template.find_one("{{Feat|type=general}}", "feat")
      assert {:error, :none} = Template.find_one("{{feature|type=general}}", "feat")
    end

    test "reports pages with no template, several templates, or unclosed braces" do
      assert {:error, :none} = Template.find_one("Just prose.", "feat")
      assert {:error, :ambiguous} = Template.find_one("{{feat|a=1}}{{feat|a=2}}", "feat")
      assert {:error, :unbalanced} = Template.find_one("{{feat|a=1", "feat")
    end

    test "records positional arguments separately instead of guessing a name" do
      assert {:ok, template} = Template.find_one("{{feat|general|type=class}}", "feat")
      assert template.positional == ["general"]
      assert template.params == %{"type" => "class"}
    end
  end
end
