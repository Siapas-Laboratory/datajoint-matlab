% dj.store_plugins.S3 - an external storage class for remove S3 endpoints.
classdef S3
    properties (Hidden, Constant)
        % mode = -1(reject), 0(optional), 1(require)
        validation_config = struct( ...
            'datajoint_type', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) && any(strcmpi(...
                        self, {'blob', 'filepath'}))...
                ), ...
            'protocol', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'location', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'subfolding', struct( ...
                    'mode', @(datajoint_type) -1 + any(strcmpi(datajoint_type, {'blob'})), ...
                    'type_check', @(self) all(floor(self) == self), ...
                    'default', [2; 2] ...
                ), ...
            'endpoint', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'bucket', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'access_key', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'secret_key', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'secure', struct( ...
                    'mode', @(datajoint_type) 0, ...
                    'type_check', @(self) islogical(self), ...
                    'default', false ...
                ) ...
            )
        backward_validation_config = struct( ...
            'protocol', struct( ...
                    'mode', @(unused) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'location', struct( ...
                    'mode', @(unused) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'subfolding', struct( ...
                    'mode', @(unused) 0, ...
                    'type_check', @(self) all(floor(self) == self), ...
                    'default', [2; 2] ...
                ), ...
            'endpoint', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'bucket', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'access_key', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'secret_key', struct( ...
                    'mode', @(datajoint_type) 1, ...
                    'type_check', @(self) ischar(self) ...
                ), ...
            'secure', struct( ...
                    'mode', @(datajoint_type) 0, ...
                    'type_check', @(self) islogical(self), ...
                    'default', false ...
                ) ...
            )
    end
    properties
        protocol
        datajoint_type
        location
        type_config
        endpoint
        bucket
        access_key
        secret_key
        web_protocol
    end
    methods
        function self = S3(config)
            % initialize store
            self.protocol = config.protocol;
            self.location = strrep(config.location, '\', '/');
            self.endpoint = config.endpoint;
            self.bucket = config.bucket;
            self.access_key = config.access_key;
            self.secret_key = config.secret_key;
            if config.secure
                self.web_protocol = 'https://';
            else
                self.web_protocol = 'http://';
            end

            self.type_config = struct();
            if dj.internal.ExternalTable.BACKWARD_SUPPORT_DJPY012 && ~any(strcmp(...
                    'datajoint_type', fieldnames(config)))
                self.type_config.subfolding = config.subfolding;
            else
                self.datajoint_type = config.datajoint_type;
                if strcmpi(self.datajoint_type, 'blob')
                    self.type_config.subfolding = config.subfolding;
                end
            end
            try
                RESTCallAWSSigned(self.web_protocol, self.endpoint, ['/' self.bucket], uint8(''), self.access_key, self.secret_key, 'put');
            catch ME
                if ~strcmp(ME.identifier,'MATLAB:webservices:HTTP409StatusCodeError')
                    rethrow(ME);
                end
            end
        end
        function external_filepath = make_external_filepath(self, relative_filepath)
            % resolve the complete external path based on the relative path
            external_filepath = ['/' self.bucket '/' self.location '/' relative_filepath];
        end
        function upload_buffer(self, buffer, external_filepath)
            % put blob
            RESTCallAWSSigned(self.web_protocol, self.endpoint, external_filepath, buffer, self.access_key, self.secret_key, 'put');
        end
        function result = download_buffer(self, external_filepath)
            % get blob
            result = RESTCallAWSSigned(self.web_protocol, self.endpoint, external_filepath, uint8(''), self.access_key, self.secret_key, 'get');
        end
        function remove_object(self, external_filepath)
            % delete an object from the store
            RESTCallAWSSigned(self.web_protocol, self.endpoint, external_filepath, uint8(''), self.access_key, self.secret_key, 'delete');
        end
    end
end
function data = RESTCallAWSSigned(protocol, host, canonical_uri, payload_bin, access_key, secret_key, method)
    % https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
    content_type = 'application/octet-stream';
    
    utctime = datetime(now,'ConvertFrom','datenum') + minutes(java.util.Date().getTimezoneOffset());
    amzdate = datestr(utctime,'yyyymmddThhMMSSZ');
    datestamp = datestr(utctime,'yyyymmdd');
    
    payload_hash = dj.lib.DataHash(payload_bin, 'bin', 'hex', 'SHA-256');
    
    algorithm = 'AWS4-HMAC-SHA256';
    region = 'us-east-1';
    service = 's3';
    credential_scope = [datestamp '/' region '/' service '/' 'aws4_request'];
    signed_headers = 'host;x-amz-date';
    
    signing_key = getSignatureKey(secret_key, datestamp, region, service);
    canonical_querystring = '';
    canonical_headers = ['host:' host newline 'x-amz-date:' amzdate newline];
    canonical_request = [upper(method) newline canonical_uri newline canonical_querystring newline canonical_headers newline signed_headers newline payload_hash];
    string_to_sign = [algorithm newline amzdate newline credential_scope newline dj.lib.DataHash(uint8(canonical_request), 'bin', 'hex', 'SHA-256')];
    signature = lower(dj.lib.HMAC(signing_key, string_to_sign, 'SHA-256'));
    authorization_header = [algorithm ' ' 'Credential=' access_key '/' credential_scope ', '  'SignedHeaders=' signed_headers ', ' 'Signature=' signature];
    
    headers = {...
        'content_type', content_type; ...
        'host', host; ...
        'X-Amz-Date', amzdate; ...
        'X-Amz-Content-Sha256', payload_hash; ...
        'Authorization', authorization_header...
    };

    options = weboptions('HeaderFields', headers, 'RequestMethod', lower(method), 'ContentType', 'binary', 'MediaType', content_type, 'CharacterEncoding', 'ISO-8859-1');
    url = [protocol host canonical_uri '?' canonical_querystring];
    if strcmpi(method, 'get')
        data = webread(url, options);
    else
        data = webwrite(url, char(payload_bin'), options);
    end
end
function kSigning = getSignatureKey(key, dateStamp, regionName, serviceName)
    kDate = sign(['AWS4' key], dateStamp);
    kRegion = sign(kDate, regionName);
    kService = sign(kRegion, serviceName);
    kSigning = sign(kService, 'aws4_request');
end
function signature = sign(key, msg)
    signature = dj.lib.HMAC(key, msg, 'SHA-256');
    %disp(signature);
    hexstring = signature';
    reshapedString = reshape(hexstring,2,32);
    hexMtx = reshapedString.';
    decMtx = hex2dec(hexMtx);
    signature = char(uint8(decMtx)');
end
