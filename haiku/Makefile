## Shiori for Haiku: Haiku's makefile-engine. `make` builds objects.*/Shiori.
## The headless core test is Makefile.test (Linux and Haiku).

NAME = Shiori
TYPE = APP
APP_MIME_SIG = application/x-vnd.machiya-kobo.shiori

SRCS = \
	core/Json.cpp \
	core/Query.cpp \
	core/Results.cpp \
	core/Config.cpp \
	core/SignIn.cpp \
	core/Outbox.cpp \
	core/NoteText.cpp \
	app/App.cpp \
	app/DeskbarView.cpp \
	app/Http.cpp \
	app/NoteWindow.cpp \
	app/QuickWindow.cpp \
	app/ResultItem.cpp \
	app/Search.cpp \
	app/SaveWindow.cpp \
	app/SearchWindow.cpp \
	app/SettingsWindow.cpp \
	app/SignInWindow.cpp

# Shiori's one version (project.yml), for the app (client_version, About)
# and its app_version resource (Version.rdef, generated, not committed).
SHIORI_VERSION := $(shell sed -n 's/.*MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\).*/\1/p' ../project.yml | head -1)
_VERSION_RDEF := $(shell sh tools/version-rdef.sh > Version.rdef)

RDEFS = Shiori.rdef Icon.rdef Version.rdef
RSRCS =

# netservices2 is private API, linked statically (libnetservices2.a); it
# needs libbnetapi for sockets/TLS.
LIBS = be bnetapi netservices2 $(STDCPPLIBS)
LIBPATHS =

SYSTEM_INCLUDE_PATHS = \
	$(shell findpaths -e B_FIND_PATH_HEADERS_DIRECTORY private/netservices2) \
	$(shell findpaths -e B_FIND_PATH_HEADERS_DIRECTORY private/support)
LOCAL_INCLUDE_PATHS = core app

OPTIMIZE := SOME
LOCALES =
DEFINES = 'SHIORI_VERSION="$(SHIORI_VERSION)"'
WARNINGS = ALL
SYMBOLS :=
DEBUGGER :=
COMPILER_FLAGS = -std=c++17
# Deskbar loads the app's binary as its item and looks up
# instantiate_deskbar_item and DeskbarView::Instantiate: export them.
LINKER_FLAGS = -Wl,--export-dynamic
APP_VERSION :=
INSTALL_DIR =
TARGET_DIR =

DEVEL_DIRECTORY := \
	$(shell findpaths -r "makefile_engine" B_FIND_PATH_DEVELOP_DIRECTORY)
include $(DEVEL_DIRECTORY)/etc/makefile-engine
