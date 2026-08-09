module BrandingHelper
  TAGLINE = "The indexer bridge that really ties the stack together."

  def bridgarr_tagline
    TAGLINE
  end

  def bridgarr_page_title
    page_title = content_for(:title).presence
    [ page_title, "Bridgarr" ].compact.join(" · ")
  end
end
