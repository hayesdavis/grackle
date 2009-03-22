module Grackle
  module Utils
    
    VALID_PROFILE_IMAGE_SIZES = [:bigger,:normal,:mini]
    
    #Easy method for getting different sized profile images using Twitter's naming scheme
    def profile_image_url(url,size=:normal)
      size = VALID_PROFILE_IMAGE_SIZES.find(:normal){|s| s == size.to_sym}
      return url if url.nil? || size == :normal
      url.sub(/_normal\./,"_#{size.to_s}.")
    end
  
    module_function :profile_image_url    
    
  end
end