#define _GNU_SOURCE
#include <assert.h>
#include <endian.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "timing.h"

static time_t clock_now;
static int checks;

time_t nlbw_test_time(time_t *out)
{
	if (out)
		*out = clock_now;
	return clock_now;
}

static void set_clock(int y, int m, int d, int h, int min, int sec)
{
	struct tm tm = { .tm_year = y - 1900, .tm_mon = m - 1,
		.tm_mday = d, .tm_hour = h, .tm_min = min, .tm_sec = sec,
		.tm_isdst = -1 };
	clock_now = mktime(&tm);
	assert(clock_now != (time_t)-1);
}

static void expect(const char *spec, int offset, int expected)
{
	struct interval iv = {0};
	assert(interval_pton(spec, &iv) == 0);
	int actual = interval_timestamp(&iv, offset);
	if (actual != expected) {
		fprintf(stderr, "%s offset %d: expected %d, got %d\n",
			spec, offset, expected, actual);
		exit(1);
	}
	checks++;
}

int main(int argc, char **argv)
{
	assert(setenv("TZ", "CST-8", 1) == 0);
	tzset();
	if (argc == 2) {
		const char *specs[] = {"2026-10-08/1", "2026-10-08/7", "2026-10-08/30", "1", "-1"};
		int offsets[] = {-100, -1, 0, 1, 100};
		for (int d = 22; d <= 25; d++) {
			set_clock(2026, 10, d, 1, 15, 0);
			for (unsigned i = 0; i < sizeof(specs)/sizeof(specs[0]); i++) {
				struct interval iv = {0};
				assert(interval_pton(specs[i], &iv) == 0);
				if (!strcmp(argv[1], "--headers"))
					printf("%s %u %llu %d\n", specs[i], iv.type,
						(unsigned long long)be64toh(iv.base), (int)be32toh(iv.value));
				else if (i > 0)
					for (unsigned j = 0; j < sizeof(offsets)/sizeof(offsets[0]); j++)
						printf("%d %s %d %d\n", d, specs[i], offsets[j], interval_timestamp(&iv, offsets[j]));
			}
		}
		return 0;
	}

	set_clock(2026, 10, 23, 23, 59, 59);
	expect("2026-10-08/1", 0, 20261023);
	clock_now++;
	expect("2026-10-08/1", 0, 20261024);
	expect("2026-10-08/1", -1, 20261023);
	expect("2026-10-08/1", -100, 20260716);
	expect("2026-10-08/1", 1, 20261025);
	set_clock(2026, 10, 24, 7, 59, 59);
	expect("2026-10-08/1", 0, 20261024);
	clock_now++;
	expect("2026-10-08/1", 0, 20261024);
	set_clock(2026, 10, 31, 23, 59, 59);
	expect("2026-10-08/1", 0, 20261031);
	clock_now++;
	expect("2026-10-08/1", 0, 20261101);
	set_clock(2026, 12, 31, 23, 59, 59);
	expect("2026-10-08/1", 0, 20261231);
	clock_now++;
	expect("2026-10-08/1", 0, 20270101);
	expect("2026-10-08/1", -1, 20261231);
	set_clock(2028, 2, 28, 23, 59, 59);
	clock_now++;
	expect("2026-10-08/1", 0, 20280229);
	set_clock(2028, 3, 1, 0, 0, 0);
	expect("2026-10-08/1", -1, 20280229);
	set_clock(2027, 3, 1, 0, 0, 0);
	expect("2026-10-08/1", -1, 20270228);

	/* Historical query labels must still include every retained date. */
	set_clock(2026, 10, 24, 1, 0, 0);
	for (int off = -100; off <= 1; off++) {
		time_t target = clock_now + (time_t)off * 86400;
		struct tm *day = localtime(&target);
		int label = (day->tm_year+1900)*10000 + (day->tm_mon+1)*100 + day->tm_mday;
		expect("2026-10-08/1", off, label);
	}
	puts("PASS: Beijing midnight, no 08:00 rollover, month/year/leap boundaries and 100-period offsets");
	printf("PASS: %d boundary and history checks\n", checks);
	return 0;
}
