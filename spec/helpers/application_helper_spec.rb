require 'spec_helper'

describe ApplicationHelper do 
  describe :nav_link do 
    it "returns the link active if it ought to be" do 
      view.stub(:current_page?).and_return(true)
      generated = '<a href="http://bikeindex.org" class="active">Bike Index blog</a>'
      helper.nav_link("Bike Index blog", "http://bikeindex.org").should eq(generated)
    end
  end

  describe :admin_nav_link do 
    it "returns link, active if it ought to be" do 
      view.stub(:controller_name).and_return("bike_token_invitations")
      generated = '<a href="/invitations" class="">Invitations</a>'
      helper.nav_link("Invitations", "/invitations").should eq(generated)
    end
  end

  describe :content_nav_class do 
    it "returns active if the section is the active_section" do 
      @active_section = "resources"
      helper.content_nav_class("resources").should eq("active-menu")
    end
  end

  describe :listicle_html do 
    it "returns the html formatted as we want" do 
      l = Listicle.new(body: "body", title: 'title', image_credits: 'credit')
      l.htmlize_content
      html = helper.listicle_html(l)
      target = '<article><div class="listicle-image-credit"><p>credit</p>' + 
        "\n" + '</div><h2 class="list-item-title">title</h2></article><article><p>body</p>' +
        "\n" + '</article>'
      html.should eq(target)
    end
  end

end
