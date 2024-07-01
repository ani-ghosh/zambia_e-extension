# install.packages(c("rvest", "httr", "stringr", "fs"))

# Load required libraries
library(rvest)
library(httr)
library(stringr)
library(fs)

# Set the base URL
base_url <- "https://www.agriculture.gov.zm/integratedportal/"

# Function to download a file
download_file <- function(url, file_name, output_dir = "downloaded_files") {
  tryCatch({
    # Create the output directory if it doesn't exist
    dir_create(output_dir, recurse = TRUE)
    
    # Full path for the file
    file_path <- file.path(output_dir, file_name)
    
    # Download the file
    response <- GET(url, write_disk(file_path, overwrite = TRUE))
    
    if (status_code(response) == 200) {
      cat("Downloaded:", file_name, "\n")
    } else {
      cat("Failed to download:", file_name, "\n")
    }
  }, error = function(e) {
    cat("Error downloading:", file_name, "\n")
  })
}


# Function to extract categories and links
extract_categories <- function(html_content) {
  page <- read_html(html_content)
  
  links <- page %>% html_nodes(".gdlr-core-text-box-item-content p a")
  
  names <- sapply(links, html_text)
  urls <- sapply(links, html_attr, "href")
  
  categories <- data.frame(name = names, url = urls, stringsAsFactors = FALSE)
  
  return(categories)
}


process_category <- function(category, output_dir) {
  cat("Processing category:", category$name, "\n")
  
  tryCatch({
    category_page <- read_html(category$url)
    
    # Function to recursively process nested categories and files
    process_nested <- function(node, current_path) {
      # Process files in this node
      files <- node %>% html_nodes("li[id^='wpfb-file']")
      for (file in files) {
        file_name <- file %>% html_node("a") %>% html_text() %>% str_trim()
        file_url <- file %>% html_node("a") %>% html_attr("data-url")
        if (!is.na(file_url) && !is.na(file_name) && file_name != "") {
          full_url <- paste0(base_url, file_url)
          download_file(full_url, file_name, current_path)
        }
      }
      
      # Process nested categories
      nested_cats <- category_page %>% html_nodes("li[id^='wpfb-cat']")
      for (cat in nested_cats) {
        cat_name <- cat %>% html_node("span.cat a") %>% html_text() %>% str_trim()
        if (!is.na(cat_name) && cat_name != "") {
          new_path <- file.path(current_path, cat_name)
          process_nested(cat, new_path)
        }
      }
    }
    
    # Start processing from the root of the category
    process_nested(category_page, file.path(output_dir, category$name))
    
  }, error = function(e) {
    cat("Error processing category:", category$name, "\n")
    print(e)
  })
}

# Main function to scrape files
scrape_files <- function(html_content, output_dir = "downloaded_files") {
  categories <- extract_categories(html_content)
  
  for (i in 1:nrow(categories)) {
    process_category(categories[i, ], output_dir)
  }
}

# Function to scrape and download files recursively
scrape_files <- function(url, output_dir = "downloaded_files") {
  tryCatch({
    # Read the page
    page <- read_html(url)
    
    # Find all download links
    downloads <- page %>% 
      html_nodes(xpath = "//span[descendant::a[contains(@href, 'wpfb_dl')]]")
    
    # Process each download link
    for (download in downloads) {
      link <- download %>% html_node("a")
      file_name <- html_text(link)
      download_url <- html_attr(link, "href")
      
      if (!is.na(download_url)) {
        download_file(download_url, file_name, output_dir)
      }
    }
    
    # Find all other links to recursively scrape
    other_links <- page %>% 
      html_nodes(xpath = "//a[not(contains(@href, 'wpfb_dl'))]") %>% 
      html_attr("href")
    
    # Recursively scrape other pages
    for (link in other_links) {
      if (!is.na(link) && !startsWith(link, "#") && !grepl("^(http|mailto|javascript)", link)) {
        full_url <- paste0(base_url, link)
        scrape_files(full_url, output_dir)
      }
    }
  }, error = function(e) {
    cat("Error processing:", url, "\n")
    print(e)
  })
}

# Start scraping from the base URL
scrape_files(base_url)

