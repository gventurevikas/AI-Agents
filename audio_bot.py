import boto3
def generate_dynamic_text(customer_name, appointment_date):
    return f"Hi {customer_name}, I hope you’re doing well! You recently had an appointment with us on {appointment_date}. How was your experience?"

def synthesize_speech(text):
    polly_client = boto3.Session(
        aws_access_key_id='YOUR_ACCESS_KEY',  # Replace with your access key
        aws_secret_access_key='YOUR_SECRET_KEY',  # Replace with your secret key
        region_name='us-west-2'  # Replace with your desired region
    ).client('polly')

    response = polly_client.synthesize_speech(
        Text=text,
        OutputFormat='mp3',
        VoiceId='Joanna'  # You can choose any available voice
    )

    # Save the audio stream to a file
    with open('output.mp3', 'wb') as audio_file:
        audio_file.write(response['AudioStream'].read())

# Example usage
customer_name = "John Doe"  # Dynamic content
appointment_date = "October 1, 2023"  # Dynamic content

dynamic_text = generate_dynamic_text(customer_name, appointment_date)
synthesize_speech(dynamic_text)