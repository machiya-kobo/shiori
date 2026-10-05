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
	app/Http.cpp \
	app/NoteWindow.cpp \
	app/ResultItem.cpp \
	app/SaveWindow.cpp \
	app/SearchWindow.cpp \
	app/SettingsWindow.cpp \
	app/SignInWindow.cpp

RDEFS = Shiori.rdef
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
DEFINES =
WARNINGS = ALL
SYMBOLS :=
DEBUGGER :=
COMPILER_FLAGS = -std=c++17
LINKER_FLAGS =
APP_VERSION :=
INSTALL_DIR =
TARGET_DIR =

DEVEL_DIRECTORY := \
	$(shell findpaths -r "makefile_engine" B_FIND_PATH_DEVELOP_DIRECTORY)
include $(DEVEL_DIRECTORY)/etc/makefile-engine
