class HomeController < ApplicationController
  before_action :authenticate_user!

  def index
    # TODO base this on provider
    @patient_count = CQM::Patient.count
    @categories = Measure.categories([:lower_is_better, :reporting_program_type])
    updated_categories = add_populations(transformcategories(change_measure_scoring))
    updated_categories.each do |category|
      category.measures.each do |measure|
        measure['id'] = measure['hqmf_id']
      end
    end 
    updated_categories
  end

  def check_authorization
    @provider = Provider.find(params[:id])
    auth = (can? :read, @provider) ? true : false
    render :json => auth.as_json
  end

  def set_reporting_period
    user = User.where(username: params[:username]).first
    unless params[:effective_start_date].blank? || params[:effective_date].blank?
      month, day, year = params[:effective_start_date].split('/')
      user.effective_start_date = Time.gm(year.to_i, month.to_i, day.to_i).to_i
      month, day, year = params[:effective_date].split('/')
      user.effective_date = Time.gm(year.to_i, month.to_i, day.to_i).to_i
      user.save! 
    end
    
    render :json => :set_reporting_period, status: 200
  end
# we are updating measure scoring to match the front end requirement for CMS529v1
  def change_measure_scoring
    updated_measure_scoring = @categories.each{|individual_category| 
                if individual_category.category == "Preventive Care"
                  individual_category.measures.each{|measures|
                    if(measures.measure_scoring == "COHORT" )
                      measures["measure_scoring"] = "PROPORTION"
                    end
                  }
                end
    }
    updated_measure_scoring
  end

  def transformcategories(categories)
    cats = categories
    cats.each do |singlecat|
      singlecat.measures.each do |mes|
        subs_hash = []
        mes.subs.each do |subs|
         if subs.sub_id.present?
           subs_array = subs
           sub_ids = subs_array["sub_id"].flatten
           short_title = subs_array["short_subtitle"].flatten
           sub_ids.each_with_index{ |el, i|
              sub_id = el.present? ? el.to_s : ""
              title =  short_title[i].present? ? short_title[i].to_s : ""
              subs_hash << {"sub_id": el, "short_subtitle": short_title[i]}
            }
          mes["subs"] = []
          mes["subs"] << subs_hash
          mes["subs"] = mes["subs"].flatten
          mes["sub_ids"] = mes["sub_ids"].flatten
          else
            mes["sub_ids"] = mes["sub_ids"].flatten
            mes["subs"] = []
            subs_hash << {"sub_id": "", "short_subtitle": ""}
            mes["subs"] << subs_hash
          end
        end
       end
    end
   cats
  end

def add_populations(categories)
 cats = categories
    cats.each do |singlecat|
      singlecat.measures.each do |mes|
        mes["populations"] = mes["populations"].flatten
        if mes.sub_ids.empty? && mes.populations.length >= 2
          mes["subs"] = []
          mes["populations"].each do |pop|
            mes.subs << {"sub_id": pop, "short_subtitle": pop}
           end
           mes["sub_ids"] = mes["populations"]
        end
      end
    end
    cats
end

private
  def validate_authorization!
    authorize! :read, HealthDataStandards::CQM::Measure
  end
end