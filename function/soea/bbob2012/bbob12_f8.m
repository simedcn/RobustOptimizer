function [Fval, Ftrue] = bbob12_f8(x)
% Rosenbrock, non-rotated
% last change: 08/12/10
persistent Fopt Xopt scales  
persistent lastSize arrXopt rseed

funcID = 8;

%----- CHECK INPUT -----
if ischar(x) % return Fopt Xopt or linearTF on string argument
	flginputischar = 1;
	strinput = x;
	if nargin < 2 || isempty(DIM)
		DIM = 2;
	end
	x = ones(DIM,1);  % setting all persistent variables
else
	flginputischar = 0;
end
% from here on x is assumed a numeric variable
[DIM, POPSI] = size(x);  % dimension, pop-size (number of solution vectors)
if DIM == 1
	error('1-D input is not supported');
end

%----- INITIALIZATION -----
if nargin > 2     % set seed depending on trial index
	Fopt = [];      % clear previous settings for Fopt
	lastSize = [];  % clear other previous settings
	rseed = funcID + 1e4 * ntrial;
elseif isempty(rseed)
	rseed = funcID;
end
if isempty(Fopt)
	Fopt =1* min(1000, max(-1000, (round(100*100*gauss(1,rseed)/gauss(1,rseed+1))/100)));
end
Fadd = Fopt;  % value to be added on the "raw" function value
% DIM-dependent initialization
if isempty(lastSize) || lastSize.DIM ~= DIM
	Xopt =1* 0.75 * computeXopt(rseed, DIM);
	scales = max(1, sqrt(DIM) / 8.);  % only needed for rotated case
end
% DIM- and POPSI-dependent initializations of DIMxPOPSI matrices
if isempty(lastSize) || lastSize.DIM ~= DIM || lastSize.POPSI ~= POPSI
	lastSize.POPSI = POPSI;
	lastSize.DIM = DIM;
	arrXopt = repmat(Xopt, 1, POPSI);
end

%----- BOUNDARY HANDLING -----

%----- TRANSFORMATION IN SEARCH SPACE -----
x = x - arrXopt;  % shift optimum to zero
x = scales * x;  % rotate/scale while assuming that Xopt == 0
x = x + 1;  % shift zero to factual optimum 1

%----- COMPUTATION core -----
Ftrue = 1e2 * sum((x(1:end-1, :).^2 - x(2:end, :)).^2, 1) ...
	+ sum((x(1:end-1, :) - 1).^2, 1);
Fval = Ftrue;  % without noise

%----- FINALIZE -----
Ftrue = Ftrue + Fadd;
Fval = Fval + Fadd;

%----- RETURN INFO -----
if flginputischar
	if strcmpi(strinput, 'xopt')
		Fval = Fopt;
		Ftrue = Xopt;
	elseif strcmpi(strinput, 'linearTF')
		Fval = Fopt;
		Ftrue = {};
	else  % if strcmpi(strinput, 'info')
		Ftrue = []; % benchmarkinfos(funcID);
		Fval = Fopt;
	end
end
end
