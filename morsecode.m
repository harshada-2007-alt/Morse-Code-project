%% MORSE CODE OVER LASER LINK USING ASK MODULATION
clc;
clear;
close all;

%% =========================================================
%                 PARAMETERS - USER INPUT
% ==========================================================

message = input('Enter the message to transmit: ', 's');

% Check empty message
if isempty(strtrim(message))
    error('Message cannot be empty.');
end

unitTime = 0.1;
fs = 10000;

fc = input('Enter carrier frequency in Hz [Default = 200]: ');
if isempty(fc)
    fc = 200;
end

SNR_dB = input('Enter SNR in dB [Default = 15]: ');
if isempty(SNR_dB)
    SNR_dB = 15;
end

% Convert message to uppercase
message = upper(strtrim(message));

%% =========================================================
%                 MORSE CODE TABLE
% ==========================================================

code = { ...
    '.-', '-...', '-.-.', '-..', '.', '..-.', '--.', '....', '..', ...
    '.---', '-.-', '.-..', '--', '-.', '---', '.--.', '--.-', '.-.', ...
    '...', '-', '..-', '...-', '.--', '-..-', '-.--', '--..', ...
    '-----', '.----', '..---', '...--', '....-', '.....', '-....', ...
    '--...', '---..', '----.'};

letters = ['A':'Z', '0':'9'];

morseMap = containers.Map(num2cell(letters), code);
reverseMap = containers.Map(code, num2cell(letters));

%% =========================================================
%                 TEXT -> MORSE CODE
% ==========================================================

words = strsplit(message, ' ');
morseWords = cell(1, length(words));

for w = 1:length(words)

    morseWords{w} = cell(1, length(words{w}));

    for i = 1:length(words{w})

        character = words{w}(i);

        if isKey(morseMap, character)
            morseWords{w}{i} = morseMap(character);
        else
            error('Invalid character "%s". Only A-Z and 0-9 are supported.', ...
                  character);
        end

    end
end

%% Create Complete Morse String

morseFull = '';

for w = 1:length(morseWords)

    morseFull = [morseFull strjoin(morseWords{w}, ' ')];

    if w < length(morseWords)
        morseFull = [morseFull ' / '];
    end

end

%% =========================================================
%                 MORSE -> ON/OFF BIT STREAM
% ==========================================================
%
% Dot  = 1 ON unit
% Dash = 3 ON units
%
% Symbol gap = 1 OFF unit
% Letter gap = 3 OFF units
% Word gap   = 7 OFF units

bits = [];

for w = 1:length(morseWords)

    for L = 1:length(morseWords{w})

        symbols = morseWords{w}{L};

        for s = 1:length(symbols)

            if symbols(s) == '.'
                onUnits = 1;
            else
                onUnits = 3;
            end

            % Add ON units
            bits = [bits ones(1, onUnits)];

            % Add symbol gap
            if s < length(symbols)
                bits = [bits 0];
            end

        end

        % Add letter gap
        if L < length(morseWords{w})
            bits = [bits 0 0 0];
        end

    end

    % Add word gap
    if w < length(morseWords)
        bits = [bits zeros(1, 7)];
    end

end

%% =========================================================
%                 TIME AXIS
% ==========================================================

samplesPerUnit = round(fs * unitTime);

t_unit = (0:samplesPerUnit-1) / fs;

% Convert each bit into samples
onOff = kron(bits, ones(1, samplesPerUnit));

% Complete time axis
t = (0:length(onOff)-1) / fs;

%% =========================================================
%                 ASK MODULATION
% ==========================================================
%
% ASK:
% Bit 1 -> Carrier ON
% Bit 0 -> Carrier OFF

carrierOneUnit = sin(2*pi*fc*t_unit);

carrier = repmat(carrierOneUnit, 1, length(bits));

% ASK signal
ask = onOff .* carrier;

%% =========================================================
%                 LASER CHANNEL + AWGN NOISE
% ==========================================================

signalPower = mean(ask.^2);

noisePower = signalPower / (10^(SNR_dB/10));

noise = sqrt(noisePower) * randn(size(ask));

% Received signal
rx = ask + noise;

%% =========================================================
%                 ENVELOPE DETECTION
% ==========================================================

windowSize = round(samplesPerUnit / 5);

env = movmean(abs(rx), windowSize);

%% =========================================================
%                 THRESHOLD DETECTION
% ==========================================================

onSamples = env(onOff == 1);
offSamples = env(onOff == 0);

onLevel = mean(onSamples);
offLevel = mean(offSamples);

thresh = (onLevel + offLevel) / 2;

%% =========================================================
%                 RECOVER BITS
% ==========================================================

rxBits = zeros(1, length(bits));

for i = 1:length(bits)

    startIndex = (i-1)*samplesPerUnit + 1;
    endIndex = i*samplesPerUnit;

    unitValue = mean(env(startIndex:endIndex));

    if unitValue > thresh
        rxBits(i) = 1;
    else
        rxBits(i) = 0;
    end

end

%% =========================================================
%                 BITS -> MORSE CODE
% ==========================================================

decodedMorse = '';

i = 1;

while i <= length(rxBits)

    %% Detect ON period

    if rxBits(i) == 1

        count = 0;

        while i <= length(rxBits) && rxBits(i) == 1
            count = count + 1;
            i = i + 1;
        end

        % 1 or 2 units = dot
        % 3 or more units = dash
        if count <= 2
            decodedMorse = [decodedMorse '.'];
        else
            decodedMorse = [decodedMorse '-'];
        end

    %% Detect OFF period

    else

        count = 0;

        while i <= length(rxBits) && rxBits(i) == 0
            count = count + 1;
            i = i + 1;
        end

        % Symbol gap
        if count <= 2

            % Do nothing

        % Letter gap
        elseif count <= 5

            decodedMorse = [decodedMorse ' '];

        % Word gap
        else

            decodedMorse = [decodedMorse ' / '];

        end

    end

end

%% =========================================================
%                 MORSE -> TEXT
% ==========================================================

decodedWords = strsplit(strtrim(decodedMorse), ' / ');

decodedText = '';

for w = 1:length(decodedWords)

    decodedLetters = strsplit(strtrim(decodedWords{w}), ' ');

    for j = 1:length(decodedLetters)

        currentCode = decodedLetters{j};

        if isKey(reverseMap, currentCode)

            decodedText = [decodedText reverseMap(currentCode)];

        end

    end

    % Add space between words
    if w < length(decodedWords)
        decodedText = [decodedText ' '];
    end

end

%% =========================================================
%                 ERROR CALCULATION
% ==========================================================

bitErrors = sum(rxBits ~= bits);

totalBits = length(bits);

BER = bitErrors / totalBits;

%% =========================================================
%                 DISPLAY RESULT
% ==========================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('     MORSE CODE VIA LASER LINK USING ASK\n');
fprintf('============================================\n');

fprintf('Original Message : %s\n', message);

fprintf('Morse Code       : %s\n', morseFull);

fprintf('Decoded Morse    : %s\n', decodedMorse);

fprintf('Decoded Message  : %s\n', decodedText);

fprintf('Bit Errors       : %d / %d\n', bitErrors, totalBits);

fprintf('Bit Error Rate   : %.4f\n', BER);

fprintf('SNR              : %.2f dB\n', SNR_dB);

fprintf('Carrier Frequency: %.2f Hz\n', fc);

fprintf('Carrier          : Sine Wave\n');

fprintf('============================================\n');

%% =========================================================
%                 MAIN PLOTS
% ==========================================================

figure('Name','Morse Code via Laser - ASK', ...
       'Position',[50 50 1100 950]);

%% Plot 1 - Morse Bit Stream

subplot(6,1,1);

plot(t, onOff, 'b', 'LineWidth', 1);

ylim([-0.2 1.2]);

grid on;

title('1. Morse Code ON/OFF Bit Stream');

xlabel('Time (s)');
ylabel('Bit');

%% Plot 2 - Carrier

subplot(6,1,2);

N2 = min(2*samplesPerUnit, length(t));

plot(t(1:N2), carrier(1:N2), ...
     'k', 'LineWidth', 1.2);

grid on;

title('2. Sine Wave Carrier - Zoomed');

xlabel('Time (s)');
ylabel('Amplitude');

%% Plot 3 - ASK Signal

subplot(6,1,3);

N3 = min(10*samplesPerUnit, length(t));

plot(t(1:N3), ask(1:N3), ...
     'r');

grid on;

title('3. ASK Signal - Sine Wave ON/OFF');

xlabel('Time (s)');
ylabel('Amplitude');

%% Plot 4 - Received Signal

subplot(6,1,4);

plot(t, rx, 'm');

grid on;

title(['4. Received Signal with Noise (SNR = ', ...
       num2str(SNR_dB), ' dB)']);

xlabel('Time (s)');
ylabel('Amplitude');

%% Plot 5 - Envelope Detection

subplot(6,1,5);

plot(t, env, 'g', 'LineWidth', 1);

hold on;

yline(thresh, '--k', 'Threshold');

grid on;

title('5. Envelope Detection and Threshold');

xlabel('Time (s)');
ylabel('Envelope');

%% Plot 6 - Transmitted vs Recovered Bits

subplot(6,1,6);

plot(t, onOff, 'b--', 'LineWidth', 1);

hold on;

recoveredWaveform = kron(rxBits, ...
                         ones(1,samplesPerUnit));

plot(t, recoveredWaveform, ...
     'r', 'LineWidth', 1);

ylim([-0.2 1.2]);

grid on;

legend('Transmitted','Recovered');

title('6. Transmitted vs Recovered Bits');

xlabel('Time (s)');
ylabel('Bit');

sgtitle(['Morse ASK | ', message, ...
         ' | Decoded: ', decodedText]);

%% =========================================================
%                 SINE WAVE FIGURE
% ==========================================================

figure('Name','Sine Wave ASK Demonstration', ...
       'Position',[150 150 1000 600]);

N = min(20*samplesPerUnit, length(t));

%% Carrier

subplot(2,1,1);

plot(t(1:N), carrier(1:N), ...
     'b', 'LineWidth', 1.5);

grid on;

title('Sine Wave Carrier');

xlabel('Time (s)');
ylabel('Amplitude');

%% ASK

subplot(2,1,2);

plot(t(1:N), ask(1:N), ...
     'r', 'LineWidth', 1.5);

grid on;

title('ASK: Sine Wave Carrier Switched ON/OFF');

xlabel('Time (s)');
ylabel('Amplitude');

%% =========================================================
%                 RESULT WINDOW
% ==========================================================

figure('Name','Transmission Result', ...
       'Position',[150 150 750 450]);

axis off;

text(0.05,0.82, ...
    ['Original Message : ', message], ...
    'FontSize',16, ...
    'FontWeight','bold');

text(0.05,0.64, ...
    ['Morse Code       : ', morseFull], ...
    'FontSize',14);

text(0.05,0.46, ...
    ['Decoded Morse    : ', decodedMorse], ...
    'FontSize',14);

text(0.05,0.28, ...
    ['Decoded Message  : ', decodedText], ...
    'FontSize',16, ...
    'FontWeight','bold');

text(0.05,0.13, ...
    ['Bit Errors        : ', ...
     num2str(bitErrors), ' / ', ...
     num2str(totalBits)], ...
     'FontSize',14);

text(0.05,0.04, ...
    ['SNR               : ', ...
     num2str(SNR_dB), ' dB'], ...
     'FontSize',12);