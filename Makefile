PROJECT = discord_api
PROJECT_DESCRIPTION = A discord api written in Erlang
PROJECT_VERSION = 0.1.0

DEPS = gun certifi lager

dep_certifi = hex 2.13.0
dep_lager = git https://github.com/erlang-lager/lager.git

SHELL_OPTS += -args_file config/vm.args -config config/sys.config -eval 'application:ensure_all_started(discord_api)'

# Compile flags
ERLC_COMPILE_OPTS= +'{parse_transform, lager_transform}'

ERLC_OPTS += $(ERLC_COMPILE_OPTS)
TEST_ERLC_OPTS += $(ERLC_COMPILE_OPTS)

REL_DEPS += relx
include erlang.mk