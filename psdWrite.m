function psdWrite(inputFolderName, outputFileName)
%------------------------------- Function Header -------------------------------
%
% Function Name:
%   psdWrite
%
% Description:
%   Produces a PSD file containing the input images as layers.
%
% Syntax:
%   psdWrite(inputFolderName, outputFileName);
%
% Inputs:
%   inputFolderName - Name or path of the folder which contains the images. If 
%                      name is given then folder must be located in the same 
%                      directory as the function.
%   outputFileName  - Name or path of the output PSD file.
%
% Example: 
%   psdWrite("images", "output");
%
% License:
%   Copyright (C) {{ 2019 }} {{ Ramzi Theodory and Serina Giha }}
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU Affero General Public License as published by
%   the Free Software Foundation, either version 3 of the License, or
%   (at your option) any later version.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU Affero General Public License for more details.
%
%   You should have received a copy of the GNU Affero General Public License
%   along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
% Authors: 
%   Ramzi Theodory and Serina Giha
%
% Last revision:
%   14. February 2019
%
%---------------------------------- Begin Code ---------------------------------

tic;

fprintf("Processing Input Images...");

startFolder = cd (inputFolderName);

imageFiles = [dir('*.jpeg'); dir('*.jpg'); dir('*.png')];

numFiles = length(imageFiles);

for i = 1:numFiles
    currentFileName = imageFiles(i).name;
    currentImage = imread(currentFileName);
    images{i} = im2uint8(currentImage); 
    numRows(i) = size(images{i}, 1);
    numColomns(i) = size(images{i}, 2);
    resolution(i) = numRows(i)*numColomns(i);
    numChannels(i) = size(images{i}, 3);
    packedBitsLength(i) = getPackedBitsLength(images{i});
end

fprintf(" Done\n");

layerCount = size(images, 2);

cd (startFolder);

% Header Data
header.formatSignature = uint8('8BPS');
header.formatVersion = [0 1];
header.reserved = [0 0 0 0 0 0];
header.numSamples = [0 numChannels(1)];
header.rows = getBytes(max(numRows), 4);
header.columns = getBytes(max(numColomns), 4);
header.bitsPerSample = [0 8];
header.colorMode = [0 3];
header.colorModeData.length = [0 0 0 0];
header.imageResources.length = [0 0 0 42];
header.imageResources.data = [56;66;73;77;3;237;0;0;0;0;0;16;0;72;0;0;0;1;0;1;0;72;0;0;0;1;0;1;56;66;73;77;4;0;0;0;0;0;0;2;0;0]'; % Don't ask I also don't know!

% Write Header data

% Check if Octave or Matlab
if exist('OCTAVE_VERSION', 'builtin') ~= 0
  if (length(regexp(outputFileName, ".*\.psd$"))==0)
    outputFileName = strcat(outputFileName, '.psd');
  end
else
  if endsWith(outputFileName, ".psd", 'IgnoreCase', true)
    outputFileName = strcat(outputFileName, '.psd');
  end
end

fprintf("Opening Output File...");

fid = fopen(outputFileName, 'w');

fprintf(" Done\n");

fprintf("Writing Header...");

writeStruct(fid, header);

fprintf(" Done\n");

[layerNames, LayernamesLength] = getLayerNames(layerCount); 

% Layer Records data
blendSig = uint8('8BIM');
blendKey = uint8('norm');
opacity = 255;
clipping = 0;
flags = 0;
filler = 0;
extraDataLength = [0 0 0 0]; 
layerMaskData = [0 0 0 0];
blendingRanges = [0 0 0 0];
compression = [0 1];

constantRecordsData = [blendSig blendKey opacity clipping flags filler extraDataLength layerMaskData blendingRanges];

for i = 1:layerCount
rectangle{i} = [0 0 0 0 0 0 0 0 getBytes(numRows(i), 4) getBytes(numColomns(i), 4)];
channels{i} = [0 numChannels(i)];
channelInfo{i} = [0 0 getBytes(packedBitsLength(i)/3, 4) 0 1 getBytes(packedBitsLength(i)/3, 4) 0 2 getBytes(packedBitsLength(i)/3, 4)];

% Records data size
RecordsData{i} =[rectangle{i} channels{i} channelInfo{i} constantRecordsData]; 
RecordsDataSize(i) = length(RecordsData{i});
end

% Layers and Masks Information Section
layersAndMasksLength = 4 + 2 + sum(RecordsDataSize) + LayernamesLength + sum(packedBitsLength) + 2;
layersAndMasks.length = getBytes(layersAndMasksLength, 4);     % layerinfolength + layercountlength layer Records size + channel image data size
layersAndMasks.layerInfoLength = getBytes(layersAndMasksLength - 4 , 4) ;
layersAndMasks.layerCount = getBytes(layerCount, 2);

fprintf("Writing Layers and Masks Information...");

writeStruct(fid, layersAndMasks);

fprintf(" Done\n");

fprintf("Writing Layer Records...");

for i = 1:layerCount
% Layer Records Section 1
layerRecords1.rectangle = rectangle{i};
layerRecords1.channels = channels{i};
layerRecords1.channelInfo = channelInfo{i};
layerRecords1.blendSig = blendSig;
layerRecords1.blendKey = blendKey;
layerRecords1.opacity = opacity;
layerRecords1.clipping = clipping;
layerRecords1.flags = flags;
layerRecords1.filler = filler;

writeStruct(fid, layerRecords1);

extraDataLength = getBytes(length(layerNames{i}) + 8, 4);
    
fwrite(fid, extraDataLength);  

% Layer Records Section 2 
layerRecords2.layerMaskData = layerMaskData;
layerRecords2.blendingRanges = blendingRanges;

writeStruct(fid, layerRecords2);
    
layerName = layerNames{i};
fwrite(fid, layerName);
end

fprintf(" Done\n");

fprintf("Writing Layers...");

fwrite(fid, compression);

for i = 1:layerCount
    fwrite(fid, packBits(images{i}));
end

fprintf(" Done\n");

fprintf("Writing Base Image...");

fwrite(fid, [0 0]); % Compression of base image

fwrite(fid, getImageVector(images{1})); % Base image is first image

fprintf(" Done\n");

fprintf("Closing and Saving Output File...");

fclose(fid);

fprintf(" Done\n");

fprintf("Write Successful! Elapsed Time: ");
fprintf(num2str(toc));
fprintf(" seconds\n");
end


function structSize = getSizeOfStruct(struct)

fields = fieldnames(struct);
numFields = size(fields, 1);

structSize = 0;

for i = 1:numFields
    
    field = struct.(fields{i});
    
    if isstruct(field)
        structSize = structSize + getSizeOfStruct(field);
    else
        structSize = structSize + length(field);
    end
    
end

end

function packedBitsLength = getPackedBitsLength(image) 
numRows = size(image, 1);
numColumns = size(image, 2);
runLength = 128;
split = ceil(numColumns/runLength);
remaining = numColumns - (runLength*(split-1));
packedBitsLength = (runLength+1)*(split-1);
packedBitsLength = packedBitsLength + (remaining+1);
packedBitsLength = packedBitsLength*numRows;
packedBitsLength = packedBitsLength + (numRows*2);
packedBitsLength = packedBitsLength + 2;
packedBitsLength = packedBitsLength*3;
end

function packedBits = packBits(image)
numRows = size(image, 1);
numColumns = size(image, 2);
numChannels = size(image, 3);
resolution = numRows*numColumns;

imageR = image(:, :, 1);
imageG = image(:, :, 2);
imageB = image(:, :, 3);

allVectors= cell(1, 3);

allVectors{1} = imageR;
allVectors{2} = imageG;
allVectors{3} = imageB;

runLength = 128;

packedBits = [];

split = ceil(numColumns/runLength);

remaining = numColumns - (runLength*(split-1));

for i = 1: size(allVectors, 2)
    
    image = allVectors{i};
    
    rle = [];
    
    for k = 1:numRows
        
        row = image(k, :);
        
        for j = 1:split-1
            rle = [rle 127 row( ((j-1)*runLength)+1 : runLength*j ) ];
        end
        
        rle = [rle remaining-1 row(end-remaining+1:end)];
        
    end
    
    rle = [repmat(getBytes(length(rle)/numRows, 2), 1, numRows) rle];
    
    rle = [rle 0 1];
    
    packedBits = [packedBits rle];
        
end
end

function [layerNames, totalLength] = getLayerNames(layerCount)
layerNames = cell(1,layerCount);
totalLength = 0;

for i=1:layerCount
        
    layerName = strcat('layer', num2str(i));
    
    layerName = uint8(layerName);
    
    layerNamelength = length(layerName);
    
    layerNamePadded = [layerNamelength layerName];
    
    if i < 10
        
         layerNamePadded = [layerNamePadded 0];

    elseif i >= 100
        
          layerNamePadded = [layerNamePadded 0 0 0];  
    
    end

    layerNames{i} = layerNamePadded;
    totalLength = totalLength + length(layerNamePadded);
    
end
end

function writeStruct(fid, struct)
fields = fieldnames(struct);
numFields = size(fields, 1);

for i = 1:numFields
    
    field = struct.(fields{i});
    
    if isstruct(field)
        writeStruct(fid, field);
    else
        fwrite(fid, field);
    end
    
end
end

function imageVector = getImageVector(image)
numRows = size(image, 1);
numColumns = size(image, 2);
resolution = numRows*numColumns;

imageR = image(:, :, 1)';
imageRVector = reshape(imageR, 1, resolution);

imageG = image(:, :, 2)';
imageGVector = reshape(imageG, 1, resolution);

imageB = image(:, :, 3)';
imageBVector = reshape(imageB, 1, resolution);

imageVector = ...
    [ ...
    imageRVector ...
    imageGVector ...
    imageBVector ...
    ];
end

function length = getBytes(layerCount, numBytes)
if numBytes == 2
    number16 = de2bi(layerCount, 16, 'left-msb');
    
    length = ...
        [ ...
        bi2de(number16(1:8), 'left-msb')
        bi2de(number16(9:16), 'left-msb')
        ];
    
    length = length';
else
    number32 = de2bi(layerCount, 32, 'left-msb');
    
    length = ...
        [ ...
        bi2de(number32(1:8), 'left-msb')
        bi2de(number32(9:16), 'left-msb')
        bi2de(number32(17:24), 'left-msb')
        bi2de(number32(25:32), 'left-msb')
        ];
    
    length = length';
end
end