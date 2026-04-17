# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'dermatlas_rnafusions_nf'
copyright = '2025, Jamie Billington'
author = 'Kim Wong, Jamie Billington'
release = '1.0.0'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = [
    "sphinx.ext.napoleon",
    "myst_parser",
    "sphinx_design",
    "sphinx_copybutton"
]

myst_enable_extensions = [
    "colon_fence",
]


templates_path = ['_templates']
exclude_patterns = []

html_theme = "sphinx_rtd_theme"
html_static_path = ['_static']

import os
import sys

sys.path.insert(0, os.path.abspath("../../src"))

source_suffix = {
    '.rst': 'restructuredtext',
    '.txt': 'markdown',
    '.md': 'markdown',
}

# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output
