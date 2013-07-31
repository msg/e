# This is an example PKGBUILD file. Use this as a start to creating your own,
# and remove these comments. For more information, see 'man PKGBUILD'.
# NOTE: Please fill out the license field for your package! If it is unknown,
# then please put 'unknown'.

# Maintainer: Your Name <youremail@domain.com>
pkgname=e
pkgver=$(date +%Y.%m.%d.%H)
pkgrel=1
epoch=
pkgdesc="E Environment Processor"
arch=('i686' 'x86_64' 'ppc' 'armv7l')
url=""
license=('GPL')
groups=()
depends=()
makedepends=()
checkdepends=()
optdepends=()
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
changelog=
source=()
noextract=()
md5sums=() #generate with 'makepkg -g'

prepare() {
	cd "$srcdir"
	ln -snf .. e
}

build() {
	cd "$srcdir/e"
	make
}

package() {
	cd "$srcdir/e"
	make DESTDIR="$pkgdir/" install
}
