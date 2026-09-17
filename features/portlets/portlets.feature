Feature: Portlets
  In order to support dynamic content on my site
  As a content editor
  I want to be able to dynamically display content.

  Background:
    Given I am logged in as a Content Editor

  Scenario: List Portlets
    When I visit /cms/portlets
    Then I should be returned to the Assets page for "Portlets"

# Login/Logout portlets replaced with devise
#  Scenario: Login portlet when logged in
#    And there is a LoginPortlet on the homepage
#    And I am editing the page at /
#    Then I should see the login portlet form
#
#  Scenario: Login portlet when logged out
#    Given there is a LoginPortlet on the homepage
#    And I am not logged in
#    And I am on the homepage
#    Then I should see the login portlet form

  Scenario: Viewing a portlet
    Given there is a "Portlet" with:
      | name          | template    |
      | A new portlet | Hello World |
    When I request /cms/content_library
    And choose to view "Portlet" from the main menu
    Then I should see the following content:
      | A new portlet |
    When I view that portlet
    Then I should see the following content:
      | Hello World |

  Scenario: Deleting a portlet
    Given there is a "Portlet" with:
      | name          | template    |
      | A new portlet | Hello World |
    When I delete that portlet
    And I request /cms/content_library
    And choose to view "Portlet" from the main menu
    And I should not see "A new portlet"

  Scenario: Editing a portlet
    Given there is a "Portlet" with:
      | name          | template    |
      | A new portlet | Hello World |
    When I edit that portlet
    And fill in "Name" with "New Name"
    And fill in "Template" with "New World"
    And I click the Save button
    Then I should see the following content:
      | View Portlet |
      | New World    |
    And I should not see the following content:
      | A new portlet |
      | Hello World   |

  Scenario: Page with portlet on it
    Given I am not logged in
    And a page with a portlet that display "Hello World" exists
    When I visit that page
    Then I should see the following content:
      | Hello World |

  Scenario: Portlet throws a 404 Error
    Given I am not logged in
    And a page with a portlet that raises a Not Found exception exists
    When I visit that page
    Then I should see the CMS 404 page

  Scenario: Portlet throws an 403 Error
    Given I am not logged in
    And a page with a portlet that raises an Access Denied exception exists
    When I visit that page
    Then I should see the CMS :forbidden page

  Scenario: Portlet throws 404 and 403 errors
    Given I am not logged in
    And a page with a portlet that raises both a 404 and 403 error exists
    When I visit that page
    Then I should see the CMS 404 page

  Scenario: Portlet throws 403 and any other error
    Given I am not logged in
    And a page with a portlet that raises both a 403 and any other error exists
    When I visit that page
    Then I should see the CMS :forbidden page

  # Inverted from "Portlet errors should not blow up the page", which was
  # @known-bug from the Phase 0 baseline onwards and could never have passed:
  # it asserted the body contained neither "Exception" nor "Error", while the
  # engine's own inline marker for a failed connectable is "Exception: <msg>".
  #
  # The assertion now matches what the engine does and what the consuming app
  # wants -- a portlet that fails takes the page to the CMS server error page
  # rather than rendering half a page. See cms's
  # config/initializers/override_bcms_partial_error_rescue.rb: "If a partial
  # errors out, we want to show the user a 500, not a partially rendered page."
  #
  # NOTE the fixture raises `Exception`, and that is load-bearing:
  # prepare_connectables_for_render rescues bare (so, StandardError), stashes
  # the error on the connectable and renders it inline. Only a non-StandardError
  # escapes to the 500. An ordinary portlet error does NOT reach this page --
  # that is pinned by the scenario below.
  Scenario: A portlet raising a non-StandardError takes the page to the 500
    Given I am not logged in
    And a portlet that throws an unexpected error exists
    When I view that page
    Then I should see the CMS :server_error page

  # Characterization, not an endorsement: this is what the engine does today
  # with an ordinary error, and it is the half-rendered page the consuming app
  # overrides the engine to avoid. Flip it if the inline rescue at
  # lib/cms/content_rendering_support.rb:99 is ever removed.
  Scenario: A portlet raising a StandardError renders inline and the page survives
    Given I am not logged in
    And a portlet that throws an ordinary error exists
    When I view that page
    Then the page should render the other content with the error inline

  Scenario: Multiple Pages
    Given there are multiple pages of portlets in the Content Library
    When I request /cms/portlets
    Then I should see the paging controls
    And I click on "next_page_link"
    Then I should see the second page of content

  Scenario: Portlets can override page titles
    Given a developer creates a portlet which sets a custom page title as "A Custom Title"
    When a guest views that page
    Then I should see a page named "A Custom Title"