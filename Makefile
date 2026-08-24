.PHONY: all app dmg test clean

all: app dmg

test:
	./scripts/test.sh

app:
	./scripts/build.sh

dmg: app
	./scripts/package-dmg.sh

clean:
	rm -rf build dist
