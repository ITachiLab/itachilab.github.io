from datetime import datetime

# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'Itachi Lab Docs'
copyright = f"{datetime.today().year}, Itachi"
author = 'Itachi'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = [
    'sphinx_rtd_theme',
    'sphinx_sitemap',
    'sphinx.ext.mathjax',
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']
highlight_language = 'text'



# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']
html_extra_path = ['.nojekyll', 'google9549684a226df657.html']
html_theme_options = {
    'logo_only': True,
    'analytics_id': 'G-7S93SGB655',
}
html_logo = 'logo.png'
html_title = 'ITachi Lab Docs'
html_css_files = [
    'css/custom.css',
]
html_baseurl = 'https://itachi.pl/'
