////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	../rtl/seqpolar.v
//
// Project:	A series of CORDIC related projects
//
// Purpose:	This is a rectangular to polar conversion routine based upon an
//		internal CORDIC implementation.  Basically, the input is
//	provided in i_xval and i_yval.  The internal CORDIC rotator will rotate
//	(i_xval, i_yval) until i_yval is approximately zero.  The resulting
//	xvalue and phase will be placed into o_xval and o_phase respectively.
//
//	This particular version of the polar to rectangular CORDIC converter
//	converter processes a somple one at a time.  It is completely
//	sequential, not parallel at all.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2017-2018, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
module	seqpolar(i_clk, i_reset, i_stb, i_xval, i_yval, i_aux, o_busy,
		o_done, o_mag, o_phase, o_aux);
	localparam	IW=12,	// The number of bits in our inputs
			OW=12,// The number of output bits to produce
			NSTAGES=16,
			XTRA= 3,// Extra bits for internal precision
			WW=18,	// Our working bit-width
			PW=19;	// Bits in our phase variables
	input					i_clk, i_reset, i_stb;
	input	wire	signed	[(IW-1):0]	i_xval, i_yval;
	output	wire				o_busy;
	output	reg				o_done;
	output	reg	signed	[(OW-1):0]	o_mag;
	output	reg		[(PW-1):0]	o_phase;
	input	wire				i_aux;
	output	reg				o_aux;
	// First step: expand our input to our working width.
	// This is going to involve extending our input by one
	// (or more) bits in addition to adding any xtra bits on
	// bits on the right.  The one bit extra on the left is to
	// allow for any accumulation due to the cordic gain
	// within the algorithm.
	// 
	wire	signed [(WW-1):0]	e_xval, e_yval;
	assign	e_xval = { {(2){i_xval[(IW-1)]}}, i_xval, {(WW-IW-2){1'b0}} };
	assign	e_yval = { {(2){i_yval[(IW-1)]}}, i_yval, {(WW-IW-2){1'b0}} };

	// Declare variables for all of the separate stages
	reg	signed	[(WW-1):0]	xv, yv, prex, prey;
	reg		[(PW-1):0]	ph, preph;

	//
	// Handle the auxilliary logic.
	//
	// The auxilliary bit is designed so that you can place a valid bit into
	// the CORDIC function, and see when it comes out.  While the bit is
	// allowed to be anything, the requirement of this bit is that it *must*
	// be aligned with the output when done.  That is, if i_xval and i_yval
	// are input together with i_aux, then when o_xval and o_yval are set
	// to this value, o_aux *must* contain the value that was in i_aux.
	//
	reg		aux;

	always @(posedge i_clk)
	if (i_reset)
		aux <= 0;
	else if ((i_stb)&&(!o_busy))
		aux <= i_aux;

	// First stage, map to within +/- 45 degrees
	always @(posedge i_clk)
		case({i_xval[IW-1], i_yval[IW-1]})
		2'b01: begin // Rotate by -315 degrees
			prex <=  e_xval - e_yval;
			prey <=  e_xval + e_yval;
			preph <= 19'h70000;
			end
		2'b10: begin // Rotate by -135 degrees
			prex <= -e_xval + e_yval;
			prey <= -e_xval - e_yval;
			preph <= 19'h30000;
			end
		2'b11: begin // Rotate by -225 degrees
			prex <= -e_xval - e_yval;
			prey <=  e_xval - e_yval;
			preph <= 19'h50000;
			end
		// 2'b00:
		default: begin // Rotate by -45 degrees
			prex <=  e_xval + e_yval;
			prey <= -e_xval + e_yval;
			preph <= 19'h10000;
			end
		endcase
	//
	// In many ways, the key to this whole algorithm lies in the angles
	// necessary to do this.  These angles are also our basic reason for
	// building this CORDIC in C++: Verilog just can't parameterize this
	// much.  Further, these angle's risk becoming unsupportable magic
	// numbers, hence we define these and set them in C++, based upon
	// the needs of our problem, specifically the number of stages and
	// the number of bits required in our phase accumulator
	//
	reg	[18:0]	cordic_angle [0:15];
	reg	[18:0]	cangle;

	initial	cordic_angle[ 0] = 19'h0_9720; //  26.565051 deg
	initial	cordic_angle[ 1] = 19'h0_4fd9; //  14.036243 deg
	initial	cordic_angle[ 2] = 19'h0_2888; //   7.125016 deg
	initial	cordic_angle[ 3] = 19'h0_1458; //   3.576334 deg
	initial	cordic_angle[ 4] = 19'h0_0a2e; //   1.789911 deg
	initial	cordic_angle[ 5] = 19'h0_0517; //   0.895174 deg
	initial	cordic_angle[ 6] = 19'h0_028b; //   0.447614 deg
	initial	cordic_angle[ 7] = 19'h0_0145; //   0.223811 deg
	initial	cordic_angle[ 8] = 19'h0_00a2; //   0.111906 deg
	initial	cordic_angle[ 9] = 19'h0_0051; //   0.055953 deg
	initial	cordic_angle[10] = 19'h0_0028; //   0.027976 deg
	initial	cordic_angle[11] = 19'h0_0014; //   0.013988 deg
	initial	cordic_angle[12] = 19'h0_000a; //   0.006994 deg
	initial	cordic_angle[13] = 19'h0_0005; //   0.003497 deg
	initial	cordic_angle[14] = 19'h0_0002; //   0.001749 deg
	initial	cordic_angle[15] = 19'h0_0001; //   0.000874 deg
	// Std-Dev    : 0.00 (Units)
	// Phase Quantization: 0.000030 (Radians)
	// Gain is 1.164435
	// You can annihilate this gain by multiplying by 32'hdbd95b16
	// and right shifting by 32 bits.

	reg		idle, pre_valid;
	reg	[4:0]	state;

	wire	last_state;
	assign	last_state = (state >= 17);

	initial	idle = 1'b1;
	always @(posedge i_clk)
	if (i_reset)
		idle <= 1'b1;
	else if (i_stb)
		idle <= 1'b0;
	else if (last_state)
		idle <= 1'b1;

	initial	pre_valid = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		pre_valid <= 1'b0;
	else
		pre_valid <= (i_stb)&&(idle);

	initial	state = 0;
	always @(posedge i_clk)
	if (i_reset)
		state <= 0;
	else if (idle)
		state <= 0;
	else if (last_state)
		state <= 0;
	else
		state <= state + 1;

	always @(posedge i_clk)
		cangle <= cordic_angle[state[3:0]];

	// Here's where we are going to put the actual CORDIC
	// rectangular to polar loop.  Everything up to this
	// point has simply been necessary preliminaries.
	always @(posedge i_clk)
	if (pre_valid)
	begin
		xv <= prex;
		yv <= prey;
		ph <= preph;
	end else if (yv[(WW-1)]) // Below the axis
	begin
		// If the vector is below the x-axis, rotate by
		// the CORDIC angle in a positive direction.
		xv <= xv - (yv>>>state);
		yv <= yv + (xv>>>state);
		ph <= ph - cangle;
	end else begin
		// On the other hand, if the vector is above the
		// x-axis, then rotate in the other direction
		xv <= xv + (yv>>>state);
		yv <= yv - (xv>>>state);
		ph <= ph + cangle;
	end

	always @(posedge i_clk)
	if (i_reset)
		o_done <= 1'b0;
	else
		o_done <= (last_state);

	// Round our magnitude towards even
	wire	[(WW-1):0]	final_mag;

	assign	final_mag = xv + $signed({{(OW){1'b0}},
				xv[(WW-OW)],
				{(WW-OW-1){!xv[WW-OW]}}});

	always @(posedge i_clk)
	if (last_state)
	begin
		o_mag   <= final_mag[(WW-1):(WW-OW)];
		o_phase <= ph;
		o_aux <= aux;
	end

	assign	o_busy = !idle;

	// Make Verilator happy with pre_.val
	// verilator lint_off UNUSED
	wire	[(WW-OW):0] unused_val;
	assign	unused_val = { final_mag[WW-1], final_mag[(WW-OW-1):0] };
	// verilator lint_on UNUSED
endmodule