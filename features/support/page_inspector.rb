# Support for inspecting the result of pages
module PageInspector

  # Fetch an image from page and make sure it exists.
  def get_image(css_selector)
    expect(page.body).to have_css(css_selector)
    img_tag = page.first(:css, css_selector)
    visit img_tag[:src]
    expect(page.status_code).to eq(200)
  end

  # Adds better page content assertions (Rspec like)
  def page_should_have_content(content, should_be_true=true)
    if should_be_true
      expect(page.body).to include(content) # "Couldn't find #{content}' anywhere on the page."
    else
      expect(page.body).not_to include(content) #"Found #{content}' on the page when it was not expected to be there.")
    end
  end

  def should_see_a_page_header(page_header)
    message = "Expected find <h1>#{page_header}'</h1>."
    expect(page.body).to have_css('h1', text: page_header)#, failure_message(message) { " Found instead <h1>#{find('h1').text}</h1>."}
  end

  def failure_message(message)
    if block_given?
      message << yield
    end
    message
  end
  # Both <H1> and <title> should match.
  def should_see_a_page_named(page_title)
    expect(page.body).to have_css('h1', text: page_title)
    expect(page.title).to include(page_title)
  end

  def should_see_a_page_titled(page_title)
    expect(page.title).to include(page_title)#, "Expected a page with a title '#{page_title}' but it was '#{page.title}'.")
  end

  def should_see_cms_404_page
    should_see_a_page_named "Page Not Found"
    expect(page.status_code).to eq(page.status_code)
    expect(page.body).to include("Page Not Found")
  end

  def should_be_successful
    expect(page.status_code).to eq(page.status_code) #, "While on page #{current_url}")
  end

end
World(PageInspector)
