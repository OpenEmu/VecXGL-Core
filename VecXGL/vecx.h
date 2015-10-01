#ifndef __VECX_H
#define __VECX_H

enum {
	VECTREX_MHZ		= 1500000, /* speed of the vectrex being emulated */
	VECTREX_COLORS  = 128,     /* number of possible colors ... grayscale */

	ALG_MAX_X		= 33000,
	ALG_MAX_Y		= 41000
};

enum {
	VECTREX_PDECAY	= 30,      /* phosphor decay rate */

	/* number of 6809 cycles before a frame redraw */

	FCYCLES_INIT    = VECTREX_MHZ / VECTREX_PDECAY,

	/* max number of possible vectors that maybe on the screen at one time.
	 * one only needs VECTREX_MHZ / VECTREX_PDECAY but we need to also store
	 * deleted vectors in a single table
	 */

	VECTOR_CNT		= VECTREX_MHZ / VECTREX_PDECAY,

	VECTOR_HASH     = 65521
};

typedef struct vector_type {
	long x0, y0; /* start coordinate */
	long x1, y1; /* end coordinate */

	/* color [0, VECTREX_COLORS - 1], if color = VECTREX_COLORS, then this is
	 * an invalid entry and must be ignored.
	 */
	unsigned char color;
} vector_t;

// Malban
// maximum possible offset
// offsets are "warpped"
#define ALG_MAX_OFFSET 20

// if defined you can change the
// offset settings "on the fly" by using the buttons and joytick
// debug info is printed to console
//#define ALG_DEBUG

#ifdef ALG_DEBUG
void incOffset();
void decOffset();
void change();
void alg_next();
void alg_prev();
void alg_print();
#endif

// the following 11 "flags" can be provided
// with cycle offset
// each has an own queue offset and queue counter
#define ALG_SIZE 11
enum ALG_TYPES {ZSH_DIRECT=0, Z_DIRECT, X_DIRECT, Y_DIRECT, JOY_DIRECT, COMP_DIRECT, DX_DIRECT, DY_DIRECT, COL_DIRECT, BLANK_DIRECT, RAMP_DIRECT};


typedef struct VECXState {
	//e6809 cpu regs
	unsigned cpuRegs[10];
	//vectrex ram
	unsigned char ram[1024];
	//sound chip
	unsigned sndRegs[16];
	unsigned sndSelect;
	//via 6522 regs
	unsigned viaRegs[25];
	//analog stuff
    unsigned analogDevices[4];
    unsigned alg_jsh[ALG_MAX_OFFSET];
    unsigned alg_rsh[ALG_MAX_OFFSET];
    unsigned alg_xsh[ALG_MAX_OFFSET];
    unsigned alg_ysh[ALG_MAX_OFFSET];
    unsigned alg_zsh[ALG_MAX_OFFSET];
    unsigned alg_compare[ALG_MAX_OFFSET];
    unsigned sig_ramp[ALG_MAX_OFFSET];
    unsigned sig_blank[ALG_MAX_OFFSET];

    long analogAlg[2];
    long alg_dx[ALG_MAX_OFFSET];
    long alg_dy[ALG_MAX_OFFSET];

	//vectoring stuff
	unsigned algVectoring;
	long vectorPoints[6];
    unsigned char vecColor[ALG_MAX_OFFSET];
	long vecDrawInfo[2];


    int alg_config[ALG_SIZE];
    int alg_read_positions[ALG_SIZE];
    int alg_used_offsets[ALG_SIZE];


} VECXState;

extern unsigned char ram[1024];
extern unsigned char rom[8192];

extern unsigned char get_cart(unsigned pos);
extern void set_cart(unsigned pos, unsigned char data); // only loading!

extern unsigned snd_regs[16];
extern unsigned alg_jch0;
extern unsigned alg_jch1;
extern unsigned alg_jch2;
extern unsigned alg_jch3;

extern long vector_draw_cnt;
extern long vector_erse_cnt;
extern vector_t *vectors_draw;
extern vector_t *vectors_erse;

void vecx_reset (void);
void vecx_emu (long cycles, int ahead);

VECXState * saveVecxState();
void loadVecxState(VECXState *state);

#endif
