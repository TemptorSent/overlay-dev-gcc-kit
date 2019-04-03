
case "${EAPI}" in
	5|6) inherit eapi7-ver;
esac

## Helper functions

# Run a function if it is defined
_run_function_if_exists() {
	[ "$(type -t ${1})" = "function" ] && ${1}
}

##
# Build/Crossbuild environment
# CBUILD -- Builder system
# CHOST  -- Runtime system
# CTARGET -- Target system
##

# Define any undefined C* variables to sane values
: "${CTARGET:=${CHOST:=${CBUILD}}}"
: "${CBUILD:=${CHOST}}"

# Play nice with crossdev package semantics
if [ "${CTARGET}" = "${CHOST}" ] ; then
	case "${CATEGORY}" in cross-*) export CTARGET="${CATEGORY#cross-}" ;; esac
fi

export CBUILD CHOST CTARGET

# To be defined eventually

# CHOST -m flags, need to be filtered based on CBUILD toolchain supports
: "${MCPU_FOR_CHOST:=}"
: "${MARCH_FOR_CHOST:=}"
: "${MTUNE_FOR_CHOST:=}"
: "${MABI_FOR_CHOST:=}"
: "${MFPU_FOR_CHOST:=}"
: "${MFLOAT_FOR_CHOST:=}"

# CTARGET -m flags, need to be filtered based on what current package version supports
: "${MCPU_FOR_CTARGET:=}"
: "${MCPU32_FOR_CTARGET:=}"
: "${MCPU64_FOR_CTARGET:=}"
: "${MARCH_FOR_CTARGET:=}"
: "${MARCH32_FOR_CTARGET:=}"
: "${MARCH64_FOR_CTARGET:=}"
: "${MTUNE_FOR_CTARGET:=}"
: "${MTUNE32_FOR_CTARGET:=}"
: "${MTUNE64_FOR_CTARGET:=}"
: "${MABI_FOR_CTARGET:=}"
: "${MFPU_FOR_CTARGET:=}"
: "${MFLOAT_FOR_CTARGET:=}"

# True when we are building gcc on a different tuple than we will be running it.
toolchain_gcc_is_crossbuild() {
	[ "${CBUILD:-${CHOST}}" != "${CHOST}" ]
}

# True when we will be building gcc to target a different tuple than it runs on.
toolchain_gcc_is_crosscompiler() {
	[ "${CHOST}" != "${CTARGET:-${CHOST}}" ]
}

# True when cross-building a cross-compiler.
toolchain_gcc_is_canadiancross() {
	toolchain_gcc_is_crossbuild && toolchain_gcc_is_crosscompiler
}


##
# ABI handling
##
# These imported from gentoo's toolchain.eclass -- they should change, as the presumptions don't hold for cross-build normally
: ${TARGET_ABI:=${ABI}}
: ${TARGET_MULTILIB_ABIS:=${MULTILIB_ABIS}}
: ${TARGET_DEFAULT_ABI:=${DEFAULT_ABI}}




# toolchain_gcc_version_setup <gcc-pv[r]>
toolchain_gcc_version_setup() {
	# If we've been passed an argument, treat it as our TOOLCHAIN_GCC_PVR
	[ -n "${1}" ] && TOOLCHAIN_GCC_PVR="${1}"
	# If only T.C._GCC_PVR is set, not T.C._GCC_PV, parse T.C._GCC_PVR into T.C_GCC_P[VR]
	if [ -z "${TOOLCHAIN_GCC_PV}" ] && [ -n "${TOOLCHAIN_GCC_PVR}" ] ; then
		TOOLCHAIN_GCC_PV="${TOOLCHAIN_GCC_PVR%-r*}"
		TOOLCHAIN_GCC_PR="${TOOLCHAIN_GCC_PVR##*-r}"
		if [ "${TOOLCHAIN_GCC_PV}" -eq "${TOOLCHAIN_GCC_PR}" ] ; then
			TOOLCHAIN_GCC_PR=""
		else
			TOOLCHAIN_GCC_PR="r${TOOLCHAIN_GCC_PR}"
		fi
	fi

	# Set our GCC_P{V,R,VR} variables using the TOOLCHAIN_GCC_{V,R,PVR} if given, falling back to the package version
	GCC_PV="${TOOLCHAIN_GCC_PV:=${PV}}"
	GCC_PR="${TOOLCHAIN_GCC_PR=${PR%r0}}"
	GCC_PVR="${TOOLCHAIN_GCC_PVR:=${GCC_PV}${GCC_PR:+-${GCC_PR}}}"

	# Split GCC_PV into GCC{MAJOR,MINOR,MICRO}
	GCCMAJOR="$(ver_cut 1 ${GCC_PV})"
	GCCMINOR="$(ver_cut 2 ${GCC_PV})"
	GCCMICRO="$(ver_cut 3 ${GCC_PV})"

	# Define our GCC branch version ( just GCCMAJOR since 5.0 )
	GCC_BRANCH_VER="${GCCMAJOR}"
	# Define our GCC release version as the major.minor.micro
	GCC_RELEASE_VER="${GCCMAJOR}.${GCCMINOR}.${GCCMICRO}"

	case "${GCC_PV}" in
		*_pre*) GCC_RELEASE_TYPE="pre"; GCC_ARCHIVE_VER="${GCC_PV%_pre*}-${GCC_PV##*_pre}" ; GCC_VER_EXT="${GCC_PV##*_pre}" ;;
		*_p*) GCC_RELEASE_TYPE="patch"; GCC_VER_EXT="${GCC_PV##*_p}" ;;
		*_alpha*) GCC_RELEASE_TYPE="alpha" ; GCC_VER_EXT="${GCC_PV##*_alpha}" ;;
		*_beta*) GCC_RELEASE_TYPE="beta" ; GCC_VER_EXT="${GCC_PV##*_beta}" ;;
		*_rc*) GCC_RELEASE_TYPE="rc" ; GCC_ARCHIVE_VER="${GCC_PV%_rc*}-RC-${GCC_PV##*_rc}" ; GCC_VER_EXT="${GCC_PV##*_rc}" ;;
		*) GCC_RELEASE_TYPE="release" ; GCC_ARCHIVE_VER="${GCC_RELEASE_VER}" ;;
	esac

	case "${GCC_RELEASE_TYPE}" in
		patch|alpha|beta)
			case "${GCC_VER_EXT}" in
				# Handle dates in YYYYMMDD form.
				#Y   Y    Y    Y   M    M     D    D
				2[0-9][0-9][0-9][01][0-9][0123][0-9])
					GCC_ARCHIVE_VER="${GCC_BRANCH_VER}-${GCC_VER_EXT}"
					GCC_SNAPSHOT_DATE="${GCC_VER_EXT}"
				;;
				# Otherwise, assume SVN rev.
				*)
					GCC_ARCHIVE_VER="${GCC_RELEASE_VER%.*}.0}"
					GCC_SVN_REV="${GCC_VER_EXT}"
					GCC_SVN_PATCH_NAME="gcc-${GCC_ARCHIVE_VER}-to-svn-${GCC_SVN_REV}.patch"
				;;
			esac
		;;
	esac

	# Define our GCC configuration version, including the extra info as appropriate
	GCC_CONFIG_VER="${GCC_RELEASE_VER}${GCC_VER_EXT:+-${GCC_RELEASE_TYPE}${GCC_VER_EXT}${GCC_SVN_REV:+svn}${GCC_SNAPSHOT_DATE:+snapshot}}"

	export TOOLCHAIN_GCC_PVR TOOLCHAIN_GCC_PV TOOLCHAIN_GCC_PR
	export GCC_PVR GCC_PV GCC_PR
	export GCCMAJOR GCCMINOR GCCMICRO
	export GCC_BRANCH_VER GCC_RELEASE_VER GCC_CONFIG_VER
	export GCC_RELEASE_TYPE GCC_ARCHIVE_VER

	[ -n "${GCC_SNAPSHOT_DATE}" ] && export GCC_SNAPSHOT_DATE
	[ -n "${GCC_SVN_REV}" ] && export GCC_SVN_REV GCC_SVN_PATCH_NAME
}

# Call after toolchain_gcc_version_setup
toolchain_gcc_get_src_uri() {
	: "${GCC_SRC_URI_ROOT:="ftp://gcc.gnu.org/pub/gcc"}"

	## Set URI for GCC itself.

	# Releases and svn patches from releases handled if so indicated
	if [ "${GCC_RELEASE_TYPE}" = "release" ] || [ -n "${GCC_SVN_REV}" ] ; then
		GCC_SRC_URI="${GCC_SRC_URI_ROOT}/releases/gcc-${GCC_ARCHIVE_VER}/gcc-${GCC_ARCHIVE_VER}.tar.xz"
	# Otherwise, handle prereleases and snapshots
	else
		case "${GCC_RELEASE_TYPE}" in
			pre) GCC_SRC_URI="${GCC_SRC_URI_ROOT}/prerelease-${GCC_ARCHIVE_VER}/gcc-${GCC_ARCHIVE_VER}.tar.xz" ;;
			alpha|beta|rc|patch) GCC_SRC_URI="${GCC_SRC_URI_ROOT}/snapshots/${GCC_ARCHIVE_VER}/gcc-${GCC_ARCHIVE_VER}.tar.xz" ;;
		esac
	fi

	## Set URI for SVN patches.

	if [ -n "${GCC_SVN_REV}" ] ; then
		[ -n "${GCC_SVN_PATCH_URI_ROOT}" ] && GCC_SRC_URI="${GCC_SRC_URI} ${GCC_SVN_PATCH_URI_ROOT}/${GCC_SVN_PATCH_NAME}"
	fi

	## Grab prerequisites as well if building them in-tree is enabled
	if [ "${GCC_BUILD_IN_PREREQS:-0}" != "0" ] ; then
		: "${GCC_PREREQ_GMP:="gmp-6.1.0"}"
		GCC_SRC_URI="${GCC_SRC_URI} mirror://gnu/gmp/${GCC_PREREQ_GMP}.tar.xz"
		: "${GCC_PREREQ_MPFR:="mpfr-3.1.4"}"
		GCC_SRC_URI="${GCC_SRC_URI} https://www.mpfr.org/${GCC_PREREQ_MPFR}/${GCC_PREREQ_MPFR}.tar.xz"
		: "${GCC_PREREQ_MPC:="mpc-1.0.3"}"
		GCC_SRC_URI="${GCC_SRC_URI} https://ftp.gnu.org/gnu/mpc/${GCC_PREREQ_MPC}.tar.gz"
		: "${GCC_PREREQ_ISL:="isl-0.18"}"
		GCC_SRC_URI="${GCC_SRC_URI} graphite? ( https://isl.gforge.inria.fr/${GCC_PREREQ_ISL}.tar.xz )"

		# Export these in case they were defined with default values here.
		export GCC_PREREQ_GMP GCC_PREREQ_MPFR GCC_PREREQ_MPC GCC_PREREQ_ISL
	fi

	export GCC_SRC_URI
}

# Compatibility wrapper for gentoo
get_gcc_src_uri() {
	toolchain_gcc_get_src_uri
	printf -- '%s' "${GCC_SRC_URI}"
}


# Unpack the toolchain
toolchain_gcc_src_unpack() {
	unpack ${A}

	# Move any prereqs we unpacked into the gcc source tree with the version stripped from the dir name.
	local myprereq
	for myprereq in "${GCC_PREREQ_GMP}" "${GCC_PREREQ_MPFR}" "${GCC_PREREQ_MPC}" "${GCC_PREREQ_ISL}" ; do
		[ -d "${WORKDIR}/${myprereq}" ] && mv -v "${WORKDIR}/${myprereq}" "${WORKDIR}/gcc-${GCC_RELEASE_VER}/${myprereq%%-*}"
	done
}


### THE FOLLOWING NEED REWRITES ###

toolchain_gcc_pkg_setup() {

	# Capture -march -mcpu and -mtune options to pass to build later.
	MARCH="$(printf -- "${CFLAGS}" | sed -rne 's/.*-march="?([-_[:alnum:]]+).*/\1/p')"
	MCPU="$(printf -- "${CFLAGS}" | sed -rne 's/.*-mcpu="?([-_[:alnum:]]+).*/\1/p')"
	MTUNE="$(printf -- "${CFLAGS}" | sed -rne 's/.*-mtune="?([-_[:alnum:]]+).*/\1/p')"
	MFPU="$(printf -- "${CFLAGS}" | sed -rne 's/.*-mfpu="?([-_[:alnum:]]+).*/\1/p')"
	einfo "Got CFLAGS: ${CFLAGS}"
	einfo "Got GCC_BUILD_CFLAGS: ${GCC_BUILD_CFLAGS}"
	einfo "MARCH: ${MARCH}"
	einfo "MCPU ${MCPU}"
	einfo "MTUNE: ${MTUNE}"
	einfo "MFPU: ${MFPU}"

	# Don't pass cflags/ldflags through.
	unset CFLAGS
	unset CXXFLAGS
	unset CPPFLAGS
	unset LDFLAGS
	unset GCC_SPECS # we don't want to use the installed compiler's specs to build gcc!
	unset LANGUAGES #265283
	export PREFIX="${TOOLCHAIN_PREFIX:-${EPREFIX}/usr}"


	if toolchain_gcc_is_crosscompiler; then
		BINPATH="${TOOLCHAIN_BINPATH:-${PREFIX}/${CHOST}/${CTARGET}/gcc-bin/${GCC_CONFIG_VER}}"
		HOSTLIBPATH="${PREFIX}/${CHOST}/${CTARGET}/lib/${GCC_CONFIG_VER}"
	else
		BINPATH="${TOOLCHAIN_BINPATH:=${PREFIX}/${CTARGET}/gcc-bin/${GCC_CONFIG_VER}}"
	fi

	LIBPATH="${TOOLCHAIN_LIBPATH:-${PREFIX}/lib/gcc-lib/${CTARGET}/${GCC_CONFIG_VER}}"
	DATAPATH="${TOOLCHAIN_DATAPATH:-${PREFIX}/share/gcc-data/${CTARGET}/${GCC_CONFIG_VER}}"

	INCLUDEPATH="${TOOLCHAIN_INCLUDEPATH:-${LIBPATH}/include}"
	STDCXX_INCDIR="${TOOLCHAIN_STDCXX_INCDIR:-${LIBPATH}/include/g++-v${GCC_BRANCH_VER}}"

	export CFLAGS="${GCC_BUILD_CFLAGS:--O2 -pipe}"
	export FFLAGS="$CFLAGS"
	export FCFLAGS="$CFLAGS"
	export CXXFLAGS="$CFLAGS"


	use doc || export MAKEINFO="/dev/null"
}



toolchain_gcc_src_prepare() {
	[ "${GCC_BUILD_IN_PREREQS:-0}" != "0" ] && toolchain_gcc_prepare_prereqs
	# Run preperations for dependencies first

	# Patch from release to svn branch tip for backports
	[ "x${GCC_SVN_PATCH}" = "x" ] || eapply "${GCC_SVN_PATCH}"


	if [ -n "$GENTOO_PATCHES_VER" ]; then
		einfo "Applying Gentoo patches ..."
		for my_patch in ${GENTOO_PATCHES[*]} ; do
			eapply_gentoo "${my_patch}"
		done
	fi

	#use bootstrap-lto && eapply "${FILESDIR}/Fix-bootstrap-miscompare-with-LTO-bootstrap-PR85571.patch"

	# Harden things up:
	toolchain_gcc_prepare_harden

	toolchain_gcc_is_crosscompiler && _gcc_prepare_cross

	# Ada gnat compiler bootstrap preparation
	use ada && _gcc_prepare_gnat

	# Prepare GDC for d-lang support
	use d && _gcc_prepare_gdc

	# Must be called in src_prepare by EAPI6
	eapply_user
}

toolchain_gcc_prepare_mpfr() {
	if [ -n "${MPFR_PATCH_VER}" ];  then
		[ -f "${MPFR_PATCH_FILE}" ] || die "Couldn't find mpfr patch '${MPFR_PATCH_FILE}"
		pushd "${S}/mpfr" > /dev/null || die "Couldn't change to mpfr source directory."
		patch -N -Z -p1 < "${MPFR_PATCH_FILE}" || die "Failed to apply mpfr patch '${MPFR_PATCH_FILE}'."
		popd > /dev/null
	fi
}


toolchain_gcc_prepare_prereqs() {
	local myprereq
	for myprereq in gmp mpfr mpc isl ; do
		_run_function_if_exists toolchain_gcc_prepare_${myprereq}
	done

}


toolchain_gcc_prepare_harden() {
	local gcc_hard_flags=""

	_run_function_if_exists toolchain_gcc_prepare_harden_${GCCMAJOR}

	# Enable FORTIFY_SOURCE by default
	eapply_gentoo "$(set +f ; cd "${GENTOO_PATCHES_DIR}" && echo ??_all_default-fortify-source.patch )"

	if use dev_extra_warnings ; then
		eapply_gentoo "$(set +f ; cd "${GENTOO_PATCHES_DIR}" && echo ??_all_default-warn-format-security.patch* )"
		eapply_gentoo "$(set +f ; cd "${GENTOO_PATCHES_DIR}" && echo ??_all_default-warn-trampolines.patch* )"
		if use test ; then
			ewarn "USE=dev_extra_warnings enables warnings by default which are known to break gcc's tests!"
		fi
		einfo "Additional warnings enabled by default, this may break some tests and compilations with -Werror."
	fi

	sed -e '/^ALL_CFLAGS/iHARD_CFLAGS = ' \
		-e 's|^ALL_CFLAGS = |ALL_CFLAGS = $(HARD_CFLAGS) |' \
		-i "${S}"/gcc/Makefile.in

	sed -e '/^ALL_CXXFLAGS/iHARD_CFLAGS = ' \
		-e 's|^ALL_CXXFLAGS = |ALL_CXXFLAGS = $(HARD_CFLAGS) |' \
		-i "${S}"/gcc/Makefile.in

	sed -i -e "/^HARD_CFLAGS = /s|=|= ${gcc_hard_flags} |" "${S}"/gcc/Makefile.in || die

}

toolchain_gcc_prepare_harden_6_7() {
	cat "${GENTOO_PATCHES_DIR}/$(set +f ; cd "${GENTOO_PATCHES_DIR}" && echo ??_all_extra-options.patch )" \
		| sed \
			-e '/#ifdef ENABLE_DEFAULT_SSP/,/# endif/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_SSP_ALL/ }' \
			-e '/#define STACK_CHECK_SPEC/,/#define LINK_NOW_SPEC/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_LINK_NOW/ }' \
			-e '/CPP_SPEC/,/CC1_SPEC/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_STACK_CHECK/ }' \
			-e '/#ifndef EXTRA_OPTIONS/,/OPT_fstrict_overflow/ { s/#ifndef EXTRA_OPTIONS/#ifndef SANE_FSTRICT_OVERFLOW/ }' \
		> "${T}/hardening-options.patch"
	eapply "${T}/hardening-options.patch"
	# Selectively enable features from hardening patches
	use ssp_all && gcc_hard_flags+=" -DENABLE_DEFAULT_SSP_ALL"
	use link_now && gcc_hard_flags+=" -DENABLE_DEFAULT_LINK_NOW"
	use strict_overflow || gcc_hard_flags+=" -DSANE_FSTRICT_OVERFLOW"
}

toolchain_gcc_prepare_harden_6() {
	toolchain_gcc_prepare_harden_6_7
}

toolchain_gcc_prepare_harden_7() {
	toolchain_gcc_prepare_harden_6_7
}


toolchain_gcc_prepare_harden_8() {
	# Modify gentoo patch to use our more specific hardening flags.
	cat "${GENTOO_PATCHES_DIR}/$(set +f ; cd "${GENTOO_PATCHES_DIR}" && echo ??_all_extra-options.patch )" \
		| sed \
			-e '/^+#ifdef ENABLE_ESP$/,/^+#define DEFAULT_FLAG_SCP 0$/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_SCP/g }' \
			-e '/^+#ifdef EXTRA_OPTIONS$/,/^+#define DEFAULT_FLAG_SCP 0$/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_SCP/g }' \
			-e '/^+#ifdef EXTRA_OPTIONS$/,/^+#define LINK_NOW_SPEC ""$/ { s/EXTRA_OPTIONS/ENABLE_DEFAULT_LINK_NOW/g }' \
		> "${T}/hardening-options.patch"
	eapply "${T}/hardening-options.patch"
	# Selectively enable features from hardening patches
	use ssp_all && gcc_hard_flags+=" -DENABLE_DEFAULT_SSP_ALL"
	use link_now && gcc_hard_flags+=" -DENABLE_DEFAULT_LINK_NOW"
	use stack_clash_protection && gcc_hard_flags+=" -DENABLE_DEFAULT_SCP"
}

toolchain_gcc_conf_append() {
	declare -a TOOLCHAIN_GCC_CONF
	TOOLCHAIN_GCC_CONF+=( "$@" )
	declare -a -x TOOLCHAIN_GCC_CONF
}

toolchain_gcc_conf_for_newlib() {
	local myconf=(
		--with-newlib
	)
	toolchain_gcc_conf_append "${myconf[@]}"
}

toolchain_gcc_conf_for_glibc() {
	local myconf=(
		--enable-__cxa_atexit
	)
	toolchain_gcc_conf_append "${myconf[@]}"
}
