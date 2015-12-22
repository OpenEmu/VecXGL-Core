#include <stdio.h>
#include <string.h>
#include "e6809.h"
#include "e8910.h"
#include "vecx.h"
#include "osint.h"
#import "VectrexGameCore.h"

#define einline __inline

unsigned char rom[8192];
unsigned char cart[65536];
unsigned char ram[1024];
extern unsigned newbankswitchOffset = 0;
extern unsigned bankswitchOffset = 0;
unsigned char get_cart(unsigned pos) {return cart[(pos+bankswitchOffset)%65536];}
void set_cart(unsigned pos, unsigned char data){cart[(pos)%65536] = data;} // only loading therefor no bankswicthing!

#define BS_0 0
#define BS_1 0
#define BS_2 0
#define BS_3 0
#define BS_4 0
#define BS_5 0
unsigned bankswitchstate = BS_0;

/* the sound chip registers */

unsigned snd_regs[16];
static unsigned snd_select;

/* the via 6522 registers */

static unsigned via_ora;
static unsigned via_orb;
static unsigned via_ddra;
static unsigned via_ddrb;
static unsigned via_t1on;  /* is timer 1 on? */
static unsigned via_t1int; /* are timer 1 interrupts allowed? */
static unsigned via_t1c;
static unsigned via_t1ll;
static unsigned via_t1lh;
static unsigned via_t1pb7; /* timer 1 controlled version of pb7 */
static unsigned via_t2on;  /* is timer 2 on? */
static unsigned via_t2int; /* are timer 2 interrupts allowed? */
static unsigned via_t2c;
static unsigned via_t2ll;
static unsigned via_sr;
static unsigned via_srb;   /* number of bits shifted so far */
static unsigned via_src;   /* shift counter */
static unsigned via_srclk;
static unsigned via_acr;
static unsigned via_pcr;
static unsigned via_ifr;
static unsigned via_ier;
static unsigned via_ca2;
static unsigned via_cb2h;  /* basic handshake version of cb2 */
static unsigned via_cb2s;  /* version of cb2 controlled by the shift register */

/* analog devices */


static int ALL_DIRECT  = 0;

// Malban
// some analag "registers" and 2 signals are
// now provided with the possibilty of cycle offstes

// these are "zero active" :-)
// meaning only offsets are per default configured for: "COMP_DIRECT","DX_DIRECT","DY_DIRECT","COL_DIRECT", "RAMP_DIRECT"
int alg_config[ALG_SIZE]            ={1,1,1,1,1,1,0,0,0,1,0};
int alg_read_positions[ALG_SIZE]    ={0.0,0,0,0,0,0,0,0,0,0};
int alg_used_offsets[ALG_SIZE]      ={9,9,9,9,9,9,9,9,9,9,9};
char* alg_names[]                   ={"ZSH_DIRECT","Z_DIRECT","X_DIRECT","Y_DIRECT","JOY_DIRECT","COMP_DIRECT","DX_DIRECT","DY_DIRECT","COL_DIRECT", "BLANK_DIRECT", "RAMP_DIRECT"};

// debug stuff
#ifdef ALG_DEBUG
int sel = 0;
void incOffset()
{
    alg_used_offsets[sel]++;
    NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[sel], alg_config[sel] ,alg_used_offsets[sel]]);
}
void decOffset()
{
    alg_used_offsets[sel]--;
    NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[sel], alg_config[sel] ,alg_used_offsets[sel]]);
}

void alg_print()
{
    NSLog(@"***");
    for (int i=0; i<ALG_SIZE; i++)
        NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[i], alg_config[i] ,alg_used_offsets[i]]);
    NSLog(@"***");
}

void change()
{
    if (alg_config[sel]==0) alg_config[sel] = 1; else alg_config[sel] = 0;
    NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[sel], alg_config[sel] ,alg_used_offsets[sel]]);
}
void alg_next()
{
    sel = (sel+1) %ALG_SIZE;
    NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[sel], alg_config[sel] ,alg_used_offsets[sel]]);
}
void alg_prev()
{
    sel = ((sel-1)+ALG_SIZE) %ALG_SIZE;
    NSLog([@"" stringByAppendingFormat: @"%s: usage %d: offset %d",alg_names[sel], alg_config[sel] ,alg_used_offsets[sel]]);
}
#endif

// looks weird
// but once they are in place
// one tends to make less mistakes
//
// write > writes tp the queue, ahead corresponding to the configured offset
// read reads "now"
// read direct reads the offsetted value, the value from the "future"
#define ALG_DIRECT_READ(alg) {if ((ALL_DIRECT == 1) || (alg_config[alg] == 1)) return values[0]; return values[(alg_read_positions[alg]+(alg_used_offsets[alg]-1))%ALG_MAX_OFFSET];}
#define ALG_READ(alg) {if ((ALL_DIRECT == 1) || (alg_config[alg] == 1)) return values[0]; return values[alg_read_positions[alg]];}
#define ALG_WRITE(alg) {if ((ALL_DIRECT == 1) || (alg_config[alg] == 1)) values[0] = value; else values[(alg_read_positions[alg]+(alg_used_offsets[alg]-1))%ALG_MAX_OFFSET] = value;}
#define ALG_ONE_STEP(alg) {if ((ALL_DIRECT == 1) || (alg_config[alg] == 1)) return; values[(alg_read_positions[alg]+(alg_used_offsets[alg]-1)+1)%ALG_MAX_OFFSET] = values[((alg_read_positions[alg]+(alg_used_offsets[alg]-1) ) %ALG_MAX_OFFSET)];}


// these are all just helper functions so that the code below doesnt get to bloated
// easier accessablity for the arrays in which the offset data is stored

// one step ... each cycle the queue pointer moves one forward .-)
void oneStepAheadUnsigned(unsigned * values, int alg) ALG_ONE_STEP(alg)
void oneStepAheadLong(long * values, int alg) ALG_ONE_STEP(alg)
void oneStepAheadUChar(unsigned char * values, int alg) ALG_ONE_STEP(alg)

// getter and setter
// these have the names of the old variables, only "get_" "getDirect_" or "set" in front
unsigned getAlgDirectUnsigned(unsigned * values, int alg) ALG_DIRECT_READ(alg)
unsigned getAlgUnsigned(unsigned * values, int alg) ALG_READ(alg)
void setAlgUnsigned(unsigned value, unsigned * values, int alg) ALG_WRITE(alg)
long getAlgDirectLong(long * values, int alg) ALG_DIRECT_READ(alg)
long getAlgLong(long * values, int alg) ALG_READ(alg)
void setAlgLong(long value, long * values, int alg) ALG_WRITE(alg)
unsigned char getAlgDirectUChar(unsigned char * values, int alg) ALG_DIRECT_READ(alg)
unsigned char getAlgUChar(unsigned char * values, int alg) ALG_READ(alg)
void setAlgUChar(unsigned char value, unsigned char * values, int alg) ALG_WRITE(alg)

// new
// sigs - at least these two - are really more kind of "alg" :-)
static unsigned sig_ramp[ALG_MAX_OFFSET];
unsigned getDirect_sig_ramp() {return getAlgDirectUnsigned(sig_ramp, RAMP_DIRECT);}
unsigned get_sig_ramp() {return getAlgUnsigned(sig_ramp, RAMP_DIRECT);}
void set_sig_ramp(unsigned value) {setAlgUnsigned(value, sig_ramp, RAMP_DIRECT);}

static unsigned sig_blank[ALG_MAX_OFFSET];
unsigned getDirect_sig_blank() {return getAlgDirectUnsigned(sig_blank, BLANK_DIRECT);}
unsigned get_sig_blank() {return getAlgUnsigned(sig_blank, BLANK_DIRECT);}
void set_sig_blank(unsigned value) {setAlgUnsigned(value, sig_blank, BLANK_DIRECT);}

//
static unsigned alg_rsh[ALG_MAX_OFFSET];  /* zero ref sample and hold */
unsigned getDirect_alg_rsh() {return getAlgDirectUnsigned(alg_rsh, ZSH_DIRECT);}
unsigned get_alg_rsh() {return getAlgUnsigned(alg_rsh, ZSH_DIRECT);}
void set_alg_rsh(unsigned value) {setAlgUnsigned(value, alg_rsh, ZSH_DIRECT);}

static unsigned alg_xsh[ALG_MAX_OFFSET];  /* x sample and hold */
unsigned getDirect_alg_xsh() {return getAlgDirectUnsigned(alg_xsh, X_DIRECT);}
unsigned get_alg_xsh() {return getAlgUnsigned(alg_xsh, X_DIRECT);}
void set_alg_xsh(unsigned value) {setAlgUnsigned(value, alg_xsh, X_DIRECT);}

static unsigned alg_ysh[ALG_MAX_OFFSET];  /* y sample and hold */
unsigned getDirect_alg_ysh() {return getAlgDirectUnsigned(alg_ysh, Y_DIRECT);}
unsigned get_alg_ysh() {return getAlgUnsigned(alg_ysh, Y_DIRECT);}
void set_alg_ysh(unsigned value) {setAlgUnsigned(value, alg_ysh, Y_DIRECT);}

static unsigned alg_zsh[ALG_MAX_OFFSET];  /* z sample and hold */
unsigned getDirect_alg_zsh() {return getAlgDirectUnsigned(alg_zsh, Z_DIRECT);}
unsigned get_alg_zsh() {return getAlgUnsigned(alg_zsh, Z_DIRECT);}
void set_alg_zsh(unsigned value) {setAlgUnsigned(value, alg_zsh, Z_DIRECT);}

// not queued
unsigned alg_jch0;		  /* joystick direction channel 0 */
unsigned alg_jch1;		  /* joystick direction channel 1 */
unsigned alg_jch2;		  /* joystick direction channel 2 */
unsigned alg_jch3;		  /* joystick direction channel 3 */

static unsigned alg_jsh[ALG_MAX_OFFSET];  /* joystick sample and hold */
unsigned getDirect_alg_jsh() {return getAlgDirectUnsigned(alg_jsh, JOY_DIRECT);}
unsigned get_alg_jsh() {return getAlgUnsigned(alg_jsh, JOY_DIRECT);}
void set_alg_jsh(unsigned value) {setAlgUnsigned(value, alg_jsh, JOY_DIRECT);}

static unsigned alg_compare[ALG_MAX_OFFSET];
unsigned getDirect_alg_compare() {return getAlgDirectUnsigned(alg_compare, COMP_DIRECT);}
unsigned get_alg_compare() {return getAlgUnsigned(alg_compare, COMP_DIRECT);}
void set_alg_compare(unsigned value) {setAlgUnsigned(value, alg_compare, COMP_DIRECT);}

static long alg_dx[ALG_MAX_OFFSET];     /* delta x */
long getDirect_alg_dx() {return getAlgDirectLong(alg_dx, DX_DIRECT);}
long get_alg_dx() {return getAlgLong(alg_dx, DX_DIRECT);}
void set_alg_dx(long value) {setAlgLong(value, alg_dx, DX_DIRECT);}

static long alg_dy[ALG_MAX_OFFSET];     /* delta y */
long getDirect_alg_dy() {return getAlgDirectLong(alg_dy, DY_DIRECT);}
long get_alg_dy() {return getAlgLong(alg_dy, DY_DIRECT);}
void set_alg_dy(long value) {setAlgLong(value, alg_dy, DY_DIRECT);}

// not queued
static long alg_curr_x; /* current x position */
static long alg_curr_y; /* current y position */

static unsigned alg_vectoring; /* are we drawing a vector right now? */
static long alg_vector_x0;
static long alg_vector_y0;
static long alg_vector_x1;
static long alg_vector_y1;
static long alg_vector_dx;
static long alg_vector_dy;
static unsigned char alg_vector_color[ALG_MAX_OFFSET];
unsigned char getDirect_alg_vector_color() {return getAlgDirectUChar(alg_vector_color, COL_DIRECT);}
unsigned char get_alg_vector_color() {return getAlgUChar(alg_vector_color, COL_DIRECT);}
void set_alg_vector_color(unsigned char value) {setAlgUChar(value, alg_vector_color, COL_DIRECT);}






long vector_draw_cnt;
long vector_erse_cnt;
static vector_t vectors_set[2 * VECTOR_CNT];
vector_t *vectors_draw;
vector_t *vectors_erse;

static long vector_hash[VECTOR_HASH];

static long fcycles;

VECXState * saveVecxState() {
	VECXState *state = malloc(sizeof(VECXState));

	saveCPUState(state->cpuRegs);

	memcpy(state->ram, ram, sizeof(unsigned char) * 1024);

	memcpy(state->sndRegs, snd_regs, sizeof(unsigned) * 16);

	state->sndSelect = snd_select;

	unsigned viaRegs[] = {via_ora, via_orb, via_ddra, via_ddrb, via_t1on, via_t1int, via_t1c, via_t1ll,
        via_t1lh, via_t1pb7, via_t2on, via_t2int, via_t2c, via_t2ll, via_sr, via_srb,
        via_src, via_srclk, via_acr, via_pcr, via_ifr, via_ier, via_ca2, via_cb2h, via_cb2s};
	memcpy(state->viaRegs, viaRegs, sizeof(unsigned) * 25);

	unsigned analogDevices[] = {alg_jch0, alg_jch1, alg_jch2, alg_jch3 };

    // yes yes save states and load states are still working
    // though the format changed ...

    memcpy(state->analogDevices, analogDevices, sizeof(unsigned) * 4);
    memcpy(state->alg_rsh, alg_rsh, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->alg_xsh, alg_xsh, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->alg_ysh, alg_ysh, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->alg_zsh, alg_zsh, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->alg_jsh, alg_jsh, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->sig_ramp, sig_ramp, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->sig_blank, sig_blank, sizeof(unsigned) * ALG_MAX_OFFSET);
    memcpy(state->alg_compare, alg_compare, sizeof(unsigned) * ALG_MAX_OFFSET);

	long analogAlg[] = {alg_curr_x, alg_curr_y};
	memcpy(state->analogAlg, analogAlg, sizeof(long) * 2);
    memcpy(state->alg_dx, alg_dx, sizeof(long) * ALG_MAX_OFFSET);
    memcpy(state->alg_dy, alg_dy, sizeof(long) * ALG_MAX_OFFSET);


	state->algVectoring = alg_vectoring;

	long vectorPoints[] = {alg_vector_x0, alg_vector_y0, alg_vector_x1, alg_vector_y1,
        alg_vector_dx, alg_vector_dy};
	memcpy(state->vectorPoints, vectorPoints, sizeof(long) * 6);

    memcpy(state->vecColor, alg_vector_color, sizeof(unsigned char) * ALG_MAX_OFFSET);

	long vecDrawInfo[] = {vector_draw_cnt, vector_erse_cnt};
	memcpy(state->vecDrawInfo, vecDrawInfo, sizeof(long) * 2);

    memcpy(state->alg_config, alg_config, sizeof(int) * ALG_SIZE);
    memcpy(state->alg_read_positions, alg_read_positions, sizeof(int) * ALG_SIZE);
    memcpy(state->alg_used_offsets, alg_used_offsets, sizeof(int) * ALG_SIZE);

	return state;
}

void loadVecxState(VECXState *state) {
	loadCPUState(state->cpuRegs);

	memcpy(ram, state->ram, sizeof(unsigned char) * 1024);

	memcpy(snd_regs, state->sndRegs, sizeof(unsigned) * 16);

	snd_select = state->sndSelect;

	via_ora = (state->viaRegs)[0];
	via_orb = (state->viaRegs)[1];
	via_ddra = (state->viaRegs)[2];
	via_ddrb = (state->viaRegs)[3];
	via_t1on = (state->viaRegs)[4];
	via_t1int = (state->viaRegs)[5];
	via_t1c = (state->viaRegs)[6];
	via_t1ll = (state->viaRegs)[7];
	via_t1lh = (state->viaRegs)[8];
	via_t1pb7 = (state->viaRegs)[9];
	via_t2on = (state->viaRegs)[10];
	via_t2int = (state->viaRegs)[11];
	via_t2c = (state->viaRegs)[12];
	via_t2ll = (state->viaRegs)[13];
	via_sr = (state->viaRegs)[14];
	via_srb = (state->viaRegs)[15];
	via_src = (state->viaRegs)[16];
	via_srclk = (state->viaRegs)[17];
	via_acr = (state->viaRegs)[18];
	via_pcr = (state->viaRegs)[19];
	via_ifr = (state->viaRegs)[20];
	via_ier = (state->viaRegs)[21];
	via_ca2 = (state->viaRegs)[22];
	via_cb2h = (state->viaRegs)[23];
	via_cb2s = (state->viaRegs)[24];

    alg_jch0 = (state->analogDevices)[0];
    alg_jch1 = (state->analogDevices)[1];
    alg_jch2 = (state->analogDevices)[2];
    alg_jch3 = (state->analogDevices)[3];

    alg_curr_x = (state->analogAlg)[0];
    alg_curr_y = (state->analogAlg)[1];

    alg_vectoring = state->algVectoring;

    alg_vector_x0 = (state->vectorPoints)[0];
    alg_vector_y0 = (state->vectorPoints)[1];
    alg_vector_x1 = (state->vectorPoints)[2];
    alg_vector_y1 = (state->vectorPoints)[3];
    alg_vector_dx = (state->vectorPoints)[4];
    alg_vector_dy = (state->vectorPoints)[5];

    for (int i=0; i<ALG_MAX_OFFSET; i++) {
        alg_rsh[i] = (state->alg_rsh)[i];
        alg_xsh[i] = (state->alg_xsh)[i];
        alg_ysh[i] = (state->alg_ysh)[i];
        alg_zsh[i] = (state->alg_zsh)[i];
        alg_jsh[i] = (state->alg_jsh)[i];
        alg_compare[i] = (state->alg_compare)[i];

        alg_dx[i] = (state->alg_dx)[i];
        alg_dy[i] = (state->alg_dy)[i];
        sig_ramp[i] = (state->sig_ramp)[i];
        sig_blank[i] = (state->sig_blank)[i];

        alg_vector_color[i] = state->vecColor[i];
    }

    memcpy(alg_config, state->alg_config, sizeof(int) * ALG_SIZE);
    memcpy(alg_read_positions, state->alg_read_positions, sizeof(int) * ALG_SIZE);
    memcpy(alg_used_offsets, state->alg_used_offsets, sizeof(int) * ALG_SIZE);




	vector_draw_cnt = (state->vecDrawInfo)[0];
	vector_erse_cnt = (state->vecDrawInfo)[1];
}

/* update the snd chips internal registers when via_ora/via_orb changes */

static einline void snd_update (void)
{
	switch (via_orb & 0x18) {
	case 0x00:
		/* the sound chip is disabled */
		break;
	case 0x08:
		/* the sound chip is sending data */
		break;
	case 0x10:
		/* the sound chip is recieving data */

		if (snd_select != 14) {
			snd_regs[snd_select] = via_ora;
            e8910_write(snd_select, via_ora);
		}

		break;
	case 0x18:
		/* the sound chip is latching an address */

		if ((via_ora & 0xf0) == 0x00) {
			snd_select = via_ora & 0x0f;
		}

		break;
	}
}

/* update the various analog values when orb is written. */

static einline void alg_update (void)
{
	switch (via_orb & 0x06) {
	case 0x00:
		set_alg_jsh(alg_jch0);

		if ((via_orb & 0x01) == 0x00) {
			/* demultiplexor is on */
			set_alg_ysh(getDirect_alg_xsh());
		}

		break;
	case 0x02:
        set_alg_jsh(alg_jch1);

		if ((via_orb & 0x01) == 0x00) {
			/* demultiplexor is on */
			set_alg_rsh(getDirect_alg_xsh());
		}

		break;
	case 0x04:
        set_alg_jsh(alg_jch2);

		if ((via_orb & 0x01) == 0x00) {
			/* demultiplexor is on */

			if (getDirect_alg_xsh() > 0x80)
            {
				set_alg_zsh(getDirect_alg_xsh() - 0x80);
			} else {
				set_alg_zsh(0);
			}
		}

		break;
	case 0x06:
		/* sound output line */
        set_alg_jsh(alg_jch3);
		break;
	}

	/* compare the current joystick direction with a reference */

	if (getDirect_alg_jsh() > getDirect_alg_xsh()) {
		set_alg_compare (0x20);
	} else {
        set_alg_compare (0);
	}

	/* compute the new "deltas" */

	set_alg_dx((long) get_alg_xsh() - (long) get_alg_rsh());
	set_alg_dy((long) get_alg_rsh() - (long) get_alg_ysh());
}

/* update IRQ and bit-7 of the ifr register after making an adjustment to
 * ifr.
 */

static einline void int_update (void)
{
	if ((via_ifr & 0x7f) & (via_ier & 0x7f)) {
		via_ifr |= 0x80;
	} else {
		via_ifr &= 0x7f;
	}
}

unsigned char read8 (unsigned address)
{
	unsigned char data = 0;

	if ((address & 0xe000) == 0xe000) {
		/* rom */

		data = rom[address & 0x1fff];
	} else if ((address & 0xe000) == 0xc000) {
		if (address & 0x800) {
			/* ram */

			data = ram[address & 0x3ff];
		} else if (address & 0x1000) {
			/* io */

			switch (address & 0xf) {
			case 0x0:
				/* compare signal is an input so the value does not come from
				 * via_orb.
				 */

				if (via_acr & 0x80) {
					/* timer 1 has control of bit 7 */

					data = (unsigned char) ((via_orb & 0x5f) | via_t1pb7 | get_alg_compare());
				} else {
					/* bit 7 is being driven by via_orb */

					data = (unsigned char) ((via_orb & 0xdf) | get_alg_compare());
				}

				break;
			case 0x1:
				/* register 1 also performs handshakes if necessary */

				if ((via_pcr & 0x0e) == 0x08) {
					/* if ca2 is in pulse mode or handshake mode, then it
					 * goes low whenever ira is read.
					 */

					via_ca2 = 0;
				}

				/* fall through */

			case 0xf:
				if ((via_orb & 0x18) == 0x08) {
					/* the snd chip is driving port a */

					data = (unsigned char) snd_regs[snd_select];
				} else {
					data = (unsigned char) via_ora;
				}

				break;
			case 0x2:
				data = (unsigned char) via_ddrb;
				break;
			case 0x3:
				data = (unsigned char) via_ddra;
				break;
			case 0x4:
				/* T1 low order counter */

				data = (unsigned char) via_t1c;
				via_ifr &= 0xbf; /* remove timer 1 interrupt flag */

				via_t1on = 0; /* timer 1 is stopped */
				via_t1int = 0;
				via_t1pb7 = 0x80;

				int_update ();

				break;
			case 0x5:
				/* T1 high order counter */

				data = (unsigned char) (via_t1c >> 8);

				break;
			case 0x6:
				/* T1 low order latch */

				data = (unsigned char) via_t1ll;
				break;
			case 0x7:
				/* T1 high order latch */

				data = (unsigned char) via_t1lh;
				break;
			case 0x8:
				/* T2 low order counter */

				data = (unsigned char) via_t2c;
				via_ifr &= 0xdf; /* remove timer 2 interrupt flag */

				via_t2on = 0; /* timer 2 is stopped */
				via_t2int = 0;

				int_update ();

				break;
			case 0x9:
				/* T2 high order counter */

				data = (unsigned char) (via_t2c >> 8);
				break;
			case 0xa:
				data = (unsigned char) via_sr;
				via_ifr &= 0xfb; /* remove shift register interrupt flag */
				via_srb = 0;
				via_srclk = 1;

				int_update ();

				break;
			case 0xb:
				data = (unsigned char) via_acr;
				break;
			case 0xc:
				data = (unsigned char) via_pcr;
				break;
			case 0xd:
				/* interrupt flag register */

				data = (unsigned char) via_ifr;
				break;
			case 0xe:
				/* interrupt enable register */

				data = (unsigned char) (via_ier | 0x80);
				break;
			}
		}
	} else if (address < 0x8000) {
		/* cartridge */

		data = get_cart(address);
	} else {
		data = 0xff;
	}

	return data;
}

void write8 (unsigned address, unsigned char data)
{
	if ((address & 0xe000) == 0xe000) {
		/* rom */
	} else if ((address & 0xe000) == 0xc000) {
		/* it is possible for both ram and io to be written at the same! */

		if (address & 0x800) {
			ram[address & 0x3ff] = data;
		}

		if (address & 0x1000) {
			switch (address & 0xf) {
			case 0x0:
        if (bankswitchstate == BS_2)
        {
          if (data == 1) bankswitchstate = BS_3; else bankswitchstate = BS_0;
        }
        else bankswitchstate = BS_0;
				via_orb = data;

				snd_update ();
				alg_update ();

				if ((via_pcr & 0xe0) == 0x80) {
					/* if cb2 is in pulse mode or handshake mode, then it
					 * goes low whenever orb is written.
					 */

					via_cb2h = 0;
				}

				break;
			case 0x1:
				/* register 1 also performs handshakes if necessary */
        if (bankswitchstate == BS_3)
        {
          if (data == 0) bankswitchstate = BS_4; else bankswitchstate = BS_0;
        }
        else bankswitchstate = BS_0;

				if ((via_pcr & 0x0e) == 0x08) {
					/* if ca2 is in pulse mode or handshake mode, then it
					 * goes low whenever ora is written.
					 */

					via_ca2 = 0;
				}

				/* fall through */

			case 0xf:
				via_ora = data;

				snd_update ();

				/* output of port a feeds directly into the dac which then
				 * feeds the x axis sample and hold.
				 */

				set_alg_xsh(data ^ 0x80);

				alg_update ();

				break;
			case 0x2:
				via_ddrb = data;
        bankswitchstate = BS_1;
        if (data & 0x40) newbankswitchOffset = 0; else newbankswitchOffset = 32768;

				break;
			case 0x3:
        if (bankswitchstate == BS_1) bankswitchstate = BS_2; else bankswitchstate = BS_0;
				via_ddra = data;
				break;
			case 0x4:
				/* T1 low order counter */
        if (bankswitchstate == BS_5)
        {
          bankswitchOffset = newbankswitchOffset;
          bankswitchstate = BS_0;
        }
				via_t1ll = data;

				break;
			case 0x5:
				/* T1 high order counter */

				via_t1lh = data;
				via_t1c = (via_t1lh << 8) | via_t1ll;
				via_ifr &= 0xbf; /* remove timer 1 interrupt flag */

				via_t1on = 1; /* timer 1 starts running */
				via_t1int = 1;
				via_t1pb7 = 0;

				int_update ();

				break;
			case 0x6:
				/* T1 low order latch */

				via_t1ll = data;
				break;
			case 0x7:
				/* T1 high order latch */

				via_t1lh = data;
				break;
			case 0x8:
				/* T2 low order latch */

				via_t2ll = data;
				break;
			case 0x9:
				/* T2 high order latch/counter */

				via_t2c = (data << 8) | via_t2ll;
				via_ifr &= 0xdf;

				via_t2on = 1; /* timer 2 starts running */
				via_t2int = 1;

				int_update ();

				break;
			case 0xa:
				via_sr = data;
				via_ifr &= 0xfb; /* remove shift register interrupt flag */
				via_srb = 0;
				via_srclk = 1;

				int_update ();

				break;
			case 0xb:
				via_acr = data;
        if (bankswitchstate == BS_4)
        {
          if (data == 0x98) bankswitchstate = BS_5; else bankswitchstate = BS_0;
        }
        else bankswitchstate = BS_0;
				break;
			case 0xc:
				via_pcr = data;


				if ((via_pcr & 0x0e) == 0x0c) {
					/* ca2 is outputting low */

					via_ca2 = 0;
				} else {
					/* ca2 is disabled or in pulse mode or is
					 * outputting high.
					 */

					via_ca2 = 1;
				}

				if ((via_pcr & 0xe0) == 0xc0) {
					/* cb2 is outputting low */

					via_cb2h = 0;
				} else {
					/* cb2 is disabled or is in pulse mode or is
					 * outputting high.
					 */

					via_cb2h = 1;
				}

				break;
			case 0xd:
				/* interrupt flag register */

				via_ifr &= ~(data & 0x7f);
				int_update ();

				break;
			case 0xe:
				/* interrupt enable register */

				if (data & 0x80) {
					via_ier |= data & 0x7f;
				} else {
					via_ier &= ~(data & 0x7f);
				}

				int_update ();

				break;
			}
		}
	} else if (address < 0x8000) {
		/* cartridge */
	}
}

void vecx_reset (void)
{
	unsigned r;

	/* ram */

	for (r = 0; r < 1024; r++) {
		ram[r] = r & 0xff;
	}

	for (r = 0; r < 16; r++) {
		snd_regs[r] = 0;
        e8910_write(r, 0);
	}

	/* input buttons */

	snd_regs[14] = 0xff;
    e8910_write(14, 0xff);

	snd_select = 0;

	via_ora = 0;
	via_orb = 0;
	via_ddra = 0;
	via_ddrb = 0;
	via_t1on = 0;
	via_t1int = 0;
	via_t1c = 0;
	via_t1ll = 0;
	via_t1lh = 0;
	via_t1pb7 = 0x80;
	via_t2on = 0;
	via_t2int = 0;
	via_t2c = 0;
	via_t2ll = 0;
	via_sr = 0;
	via_srb = 8;
	via_src = 0;
	via_srclk = 0;
	via_acr = 0;
	via_pcr = 0;
	via_ifr = 0;
	via_ier = 0;
	via_ca2 = 1;
	via_cb2h = 1;
	via_cb2s = 0;

	alg_jch0 = 128;
	alg_jch1 = 128;
	alg_jch2 = 128;
	alg_jch3 = 128;


    for (int i=0; i<ALG_MAX_OFFSET; i++) {
        alg_rsh[i] = 128;
        alg_xsh[i] = 128;
        alg_ysh[i] = 128;
        alg_zsh[i] = 0;
        alg_jsh[i] = 128;

        alg_compare[i] = 0; /* check this */

        alg_dx[i] = 0;
        alg_dy[i] = 0;

        sig_ramp[i] = 0;
        sig_blank[i] = 0;

//        alg_vector_color[i] = state->vecColor[i];
    }





	alg_curr_x = ALG_MAX_X / 2;
	alg_curr_y = ALG_MAX_Y / 2;

	alg_vectoring = 0;

	vector_draw_cnt = 0;
	vector_erse_cnt = 0;
	vectors_draw = vectors_set;
	vectors_erse = vectors_set + VECTOR_CNT;

	fcycles = FCYCLES_INIT;

	e6809_read8 = read8;
	e6809_write8 = write8;

	e6809_reset ();
}

/* perform a single cycle worth of via emulation.
 * via_sstep0 is the first postion of the emulation.
 */

static einline void via_sstep0 (void)
{
	unsigned t2shift;

	if (via_t1on) {
		via_t1c--;

		if ((via_t1c & 0xffff) == 0xffff) {
			/* counter just rolled over */

			if (via_acr & 0x40) {
				/* continuous interrupt mode */

				via_ifr |= 0x40;
				int_update ();
				via_t1pb7 = 0x80 - via_t1pb7;

				/* reload counter */

				via_t1c = (via_t1lh << 8) | via_t1ll;
			} else {
				/* one shot mode */

				if (via_t1int) {
					via_ifr |= 0x40;
					int_update ();
					via_t1pb7 = 0x80;
					via_t1int = 0;
				}
			}
		}
	}

	if (via_t2on && (via_acr & 0x20) == 0x00) {
		via_t2c--;

		if ((via_t2c & 0xffff) == 0xffff) {
			/* one shot mode */

			if (via_t2int) {
				via_ifr |= 0x20;
				int_update ();
				via_t2int = 0;
			}
		}
	}

	/* shift counter */

	via_src--;

	if ((via_src & 0xff) == 0xff) {
		via_src = via_t2ll;

		if (via_srclk) {
			t2shift = 1;
			via_srclk = 0;
		} else {
			t2shift = 0;
			via_srclk = 1;
		}
	} else {
		t2shift = 0;
	}

	if (via_srb < 8) {
		switch (via_acr & 0x1c) {
		case 0x00:
			/* disabled */
			break;
		case 0x04:
			/* shift in under control of t2 */

			if (t2shift) {
				/* shifting in 0s since cb2 is always an output */

				via_sr <<= 1;
				via_srb++;
			}

			break;
		case 0x08:
			/* shift in under system clk control */

			via_sr <<= 1;
			via_srb++;

			break;
		case 0x0c:
			/* shift in under cb1 control */
			break;
		case 0x10:
			/* shift out under t2 control (free run) */

			if (t2shift) {
				via_cb2s = (via_sr >> 7) & 1;

				via_sr <<= 1;
				via_sr |= via_cb2s;
			}

			break;
		case 0x14:
			/* shift out under t2 control */

			if (t2shift) {
				via_cb2s = (via_sr >> 7) & 1;

				via_sr <<= 1;
				via_sr |= via_cb2s;
				via_srb++;
			}

			break;
		case 0x18:
			/* shift out under system clock control */

			via_cb2s = (via_sr >> 7) & 1;

			via_sr <<= 1;
			via_sr |= via_cb2s;
			via_srb++;

			break;
		case 0x1c:
			/* shift out under cb1 control */
			break;
		}

		if (via_srb == 8) {
			via_ifr |= 0x04;
			int_update ();
		}
	}
}

/* perform the second part of the via emulation */

static einline void via_sstep1 (void)
{
	if ((via_pcr & 0x0e) == 0x0a) {
		/* if ca2 is in pulse mode, then make sure
		 * it gets restored to '1' after the pulse.
		 */

		via_ca2 = 1;
	}

	if ((via_pcr & 0xe0) == 0xa0) {
		/* if cb2 is in pulse mode, then make sure
		 * it gets restored to '1' after the pulse.
		 */

		via_cb2h = 1;
	}
}

static einline void alg_addline (long x0, long y0, long x1, long y1, unsigned char color)
{
	unsigned long key;
	long index;

	key = (unsigned long) x0;
	key = key * 31 + (unsigned long) y0;
	key = key * 31 + (unsigned long) x1;
	key = key * 31 + (unsigned long) y1;
	key %= VECTOR_HASH;

	/* first check if the line to be drawn is in the current draw list.
	 * if it is, then it is not added again.
	 */

	index = vector_hash[key];

	if (index >= 0 && index < vector_draw_cnt &&
		x0 == vectors_draw[index].x0 &&
		y0 == vectors_draw[index].y0 &&
		x1 == vectors_draw[index].x1 &&
		y1 == vectors_draw[index].y1) {
		vectors_draw[index].color = color;
	} else {
		/* missed on the draw list, now check if the line to be drawn is in
		 * the erase list ... if it is, "invalidate" it on the erase list.
		 */

		if (index >= 0 && index < vector_erse_cnt &&
			x0 == vectors_erse[index].x0 &&
			y0 == vectors_erse[index].y0 &&
			x1 == vectors_erse[index].x1 &&
			y1 == vectors_erse[index].y1) {
			vectors_erse[index].color = VECTREX_COLORS;
		}

		vectors_draw[vector_draw_cnt].x0 = x0;
		vectors_draw[vector_draw_cnt].y0 = y0;
		vectors_draw[vector_draw_cnt].x1 = x1;
		vectors_draw[vector_draw_cnt].y1 = y1;
		vectors_draw[vector_draw_cnt].color = color;
		vector_hash[key] = vector_draw_cnt;
		vector_draw_cnt++;
	}
}

/* perform a single cycle worth of analog emulation */

static einline void alg_sstep (void)
{
	long sig_dx, sig_dy;

	if ((via_acr & 0x10) == 0x10) {
		set_sig_blank(via_cb2s);
	} else {
		set_sig_blank(via_cb2h);
	}

    if (via_ca2 == 0) {
		/* need to force the current point to the 'orgin' so just
		 * calculate distance to origin and use that as dx,dy.
		 */

		sig_dx = ALG_MAX_X / 2 - alg_curr_x;
		sig_dy = ALG_MAX_Y / 2 - alg_curr_y;
	} else {
		if (via_acr & 0x80) {
			set_sig_ramp(via_t1pb7);
		} else {
			set_sig_ramp(via_orb & 0x80);
		}

		if (get_sig_ramp() == 0) {
			sig_dx = get_alg_dx();
			sig_dy = get_alg_dy();
		} else {
			sig_dx = 0;
			sig_dy = 0;
		}
	}

	if (alg_vectoring == 0) {
		if (get_sig_blank() == 1 &&
			alg_curr_x >= 0 && alg_curr_x < ALG_MAX_X &&
			alg_curr_y >= 0 && alg_curr_y < ALG_MAX_Y) {

			/* start a new vector */

			alg_vectoring = 1;
			alg_vector_x0 = alg_curr_x;
			alg_vector_y0 = alg_curr_y;
			alg_vector_x1 = alg_curr_x;
			alg_vector_y1 = alg_curr_y;
			alg_vector_dx = sig_dx;
			alg_vector_dy = sig_dy;
/* ACHTUNG*/ set_alg_vector_color((unsigned char) get_alg_zsh());
		}
	} else {
		/* already drawing a vector ... check if we need to turn it off */

		if (get_sig_blank() == 0) {
			/* blank just went on, vectoring turns off, and we've got a
			 * new line.
			 */

			alg_vectoring = 0;

			alg_addline (alg_vector_x0, alg_vector_y0,
						 alg_vector_x1, alg_vector_y1,
						 getDirect_alg_vector_color());
		} else if (sig_dx != alg_vector_dx ||
				   sig_dy != alg_vector_dy ||
/* ACHTUNG*/				   ((unsigned char) get_alg_zsh()) != get_alg_vector_color()) {

			/* the parameters of the vectoring processing has changed.
			 * so end the current line.
			 */

			alg_addline (alg_vector_x0, alg_vector_y0,
						 alg_vector_x1, alg_vector_y1,
						 get_alg_vector_color());

			/* we continue vectoring with a new set of parameters if the
			 * current point is not out of limits.
			 */

			if (alg_curr_x >= 0 && alg_curr_x < ALG_MAX_X &&
				alg_curr_y >= 0 && alg_curr_y < ALG_MAX_Y) {
				alg_vector_x0 = alg_curr_x;
				alg_vector_y0 = alg_curr_y;
				alg_vector_x1 = alg_curr_x;
				alg_vector_y1 = alg_curr_y;
				alg_vector_dx = sig_dx;
				alg_vector_dy = sig_dy;
/* ACHTUNG*/				set_alg_vector_color((unsigned char) get_alg_zsh());
			} else {
				alg_vectoring = 0;
			}
		}
	}

	alg_curr_x += sig_dx;
	alg_curr_y += sig_dy;

	if (alg_vectoring == 1 &&
		alg_curr_x >= 0 && alg_curr_x < ALG_MAX_X &&
		alg_curr_y >= 0 && alg_curr_y < ALG_MAX_Y) {

		/* we're vectoring ... current point is still within limits so
		 * extend the current vector.
		 */

		alg_vector_x1 = alg_curr_x;
		alg_vector_y1 = alg_curr_y;
	}

}
void alg_oneStepHead()
{
    oneStepAheadUnsigned(alg_rsh, ZSH_DIRECT);
    oneStepAheadUnsigned(alg_xsh, X_DIRECT);
    oneStepAheadUnsigned(alg_zsh, Z_DIRECT);
    oneStepAheadUnsigned(alg_ysh, Y_DIRECT);
    oneStepAheadUnsigned(alg_jsh, JOY_DIRECT);
    oneStepAheadUnsigned(alg_jsh, COMP_DIRECT);
    oneStepAheadUnsigned(alg_compare, COMP_DIRECT);
    oneStepAheadLong(alg_dx, DX_DIRECT);
    oneStepAheadLong(alg_dy, DY_DIRECT);
    oneStepAheadUChar(alg_vector_color, COL_DIRECT);

    oneStepAheadUnsigned(sig_ramp, RAMP_DIRECT);
    oneStepAheadUnsigned(sig_blank, BLANK_DIRECT);


    for (int i=0; i<ALG_SIZE; i++)
        alg_read_positions[i] = ((alg_read_positions[i]+1)%ALG_MAX_OFFSET);

}


void vecx_emu (long cycles, int ahead)
{
	unsigned c, icycles;

	while (cycles > 0) {
		icycles = e6809_sstep (via_ifr & 0x80, 0);

		for (c = 0; c < icycles; c++) {
            alg_update ();
			via_sstep0 ();
            alg_update ();
			alg_sstep ();

            alg_update ();
			via_sstep1 ();

            alg_oneStepHead();
		}

		cycles -= (long) icycles;

		fcycles -= (long) icycles;

		if (fcycles < 0) {
			vector_t *tmp;

			fcycles += FCYCLES_INIT;
			osint_render();

			/* everything that was drawn during this pass now now enters
			 * the erase list for the next pass.
			 */

			vector_erse_cnt = vector_draw_cnt;
			vector_draw_cnt = 0;

			tmp = vectors_erse;
			vectors_erse = vectors_draw;
			vectors_draw = tmp;
		}
	}

    //Fill buffer and call core to update sound
    e8910_callback(pWave, 882);
    [g_core updateSound:pWave len:882];

}
